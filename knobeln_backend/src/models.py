"""
Data models for the Knobeln game.
"""
from enum import Enum
from typing import List, Dict, Optional, Union
from datetime import datetime
from pydantic import BaseModel, Field, validator
import os


class GamePhase(str, Enum):
    """Phases of the Knobeln game."""
    WAITING = "WAITING"
    PICKING = "PICKING"
    GUESSING = "GUESSING"
    FINISHED = "FINISHED"


class Player(BaseModel):
    """Player model."""
    player_id: str
    player_name: str
    connection_id: Optional[str] = None
    is_creator: bool = False
    is_eliminated: bool = False
    picked_sticks: Optional[int] = None
    guess: Optional[int] = None
    last_activity: datetime = Field(default_factory=datetime.utcnow)

    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat()
        }


class Round(BaseModel):
    """Round model for tracking game rounds."""
    round_number: int
    start_time: datetime = Field(default_factory=datetime.utcnow)
    end_time: Optional[datetime] = None
    player_turn_order: List[str]  # List of player IDs in turn order
    current_turn_index: int = 0
    sticks_picked: Dict[str, int] = Field(default_factory=dict)  # player_id -> number of sticks
    guesses: Dict[str, int] = Field(default_factory=dict)  # player_id -> guess

    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat()
        }

    @property
    def current_player_id(self) -> str:
        """Get the ID of the player whose turn it is."""
        if not self.player_turn_order:
            raise ValueError("No players in turn order")
        return self.player_turn_order[self.current_turn_index % len(self.player_turn_order)]

    def next_turn(self) -> None:
        """Advance to the next player's turn."""
        self.current_turn_index += 1
        if self.current_turn_index >= len(self.player_turn_order):
            self.current_turn_index = 0


class Game(BaseModel):
    """Game model."""
    game_id: str
    created_at: datetime = Field(default_factory=datetime.utcnow)
    started_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None
    phase: GamePhase = GamePhase.WAITING
    players: Dict[str, Player] = Field(default_factory=dict)  # player_id -> Player
    current_round: Optional[Round] = None
    rounds: List[Round] = Field(default_factory=list)
    winner_id: Optional[str] = None
    loser_id: Optional[str] = None
    settings: Dict[str, Union[int, bool, str]] = Field(default_factory=dict)

    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat()
        }

    @validator('players')
    def validate_players(cls, v):
        if not v:
            raise ValueError("Game must have at least one player")
        return v

    def get_connected_players(self) -> List[Player]:
        """Get a list of players with active WebSocket connections."""
        return [p for p in self.players.values() if p.connection_id is not None]

    def get_active_players(self) -> List[Player]:
        """Get a list of players who are still in the game (not eliminated)."""
        return [p for p in self.players.values() if not p.is_eliminated]

    def start_game(self) -> None:
        """Start the game."""
        if self.phase != GamePhase.WAITING:
            raise ValueError("Game has already started")
        
        if len(self.players) < 2:
            raise ValueError("At least 2 players are required to start the game")
        
        self.phase = GamePhase.PICKING
        self.started_at = datetime.utcnow()
        self._start_new_round()

    def _start_new_round(self) -> None:
        """Start a new round of the game."""
        if self.current_round and not self.current_round.end_time:
            self.current_round.end_time = datetime.utcnow()
            self.rounds.append(self.current_round)
        
        round_number = len(self.rounds) + 1
        active_players = self.get_active_players()
        
        # Rotate the player order for the new round
        player_order = [p.player_id for p in active_players]
        if round_number > 1:
            # Start with the next player from the previous round
            next_player_index = (round_number - 1) % len(player_order)
            player_order = player_order[next_player_index:] + player_order[:next_player_index]
        
        self.current_round = Round(
            round_number=round_number,
            player_turn_order=player_order
        )
        
        # Reset player states for the new round
        for player in active_players:
            player.picked_sticks = None
            player.guess = None
        
        self.phase = GamePhase.PICKING

    def pick_sticks(self, player_id: str, count: int) -> None:
        """Handle a player picking sticks."""
        if self.phase != GamePhase.PICKING:
            raise ValueError("It's not the picking phase")
        
        if player_id not in self.players:
            raise ValueError("Player not found in this game")
        
        if not 0 <= count <= 3:
            raise ValueError("You must pick between 0 and 3 sticks")
        
        player = self.players[player_id]
        player.picked_sticks = count
        
        # Check if all players have picked
        active_players = self.get_active_players()
        if all(p.picked_sticks is not None for p in active_players):
            self.phase = GamePhase.GUESSING
            self.current_round.sticks_picked = {
                p.player_id: p.picked_sticks for p in active_players
            }

    def make_guess(self, player_id: str, guess: int) -> None:
        """Handle a player making a guess for the total number of sticks."""
        if self.phase != GamePhase.GUESSING:
            raise ValueError("It's not the guessing phase")
        
        if player_id not in self.players:
            raise ValueError("Player not found in this game")
        
        player = self.players[player_id]
        
        # Check if it's the player's turn
        if player_id != self.current_round.current_player_id:
            raise ValueError("It's not your turn to guess")
        
        # Validate the guess
        active_players = self.get_active_players()
        min_possible = 0
        max_possible = 3 * len(active_players)
        
        if not min_possible <= guess <= max_possible:
            raise ValueError(f"Guess must be between {min_possible} and {max_possible}")
        
        # Check if the guess is already taken by another player
        if guess in self.current_round.guesses.values():
            # If it's the last player, they must choose a different number
            if len(self.current_round.guesses) == len(active_players) - 1:
                raise ValueError("This guess is already taken. Please choose a different number.")
        
        # Record the guess
        player.guess = guess
        self.current_round.guesses[player_id] = guess
        
        # Move to the next player or end the round
        if len(self.current_round.guesses) < len(active_players):
            self.current_round.next_turn()
        else:
            self._end_round()
    
    def _end_round(self) -> None:
        """End the current round and determine the results."""
        if not self.current_round:
            raise ValueError("No active round to end")
        
        self.current_round.end_time = datetime.utcnow()
        
        # Calculate the total number of sticks picked
        total_sticks = sum(self.current_round.sticks_picked.values())
        
        # Check each player's guess
        correct_guessers = []
        for player_id, guess in self.current_round.guesses.items():
            if guess == total_sticks:
                correct_guessers.append(player_id)
        
        # Handle the results
        if correct_guessers:
            # If multiple players guessed correctly, the one who guessed first wins
            if len(correct_guessers) > 1:
                # Find the player who guessed first
                first_correct = min(
                    correct_guessers,
                    key=lambda pid: self.current_round.player_turn_order.index(pid)
                )
                correct_guessers = [first_correct]
            
            # Eliminate the correct guesser(s)
            for player_id in correct_guessers:
                self.players[player_id].is_eliminated = True
        
        # Check if the game is over
        active_players = self.get_active_players()
        if len(active_players) <= 1:
            self.phase = GamePhase.FINISHED
            self.ended_at = datetime.utcnow()
            
            if len(active_players) == 1:
                self.loser_id = active_players[0].player_id
        else:
            # Start a new round
            self._start_new_round()
        
        # Add the completed round to the history
        self.rounds.append(self.current_round)


class GameEvent(BaseModel):
    """Event model for game state changes."""
    event_type: str
    game_id: str
    player_id: Optional[str] = None
    data: dict = Field(default_factory=dict)
    timestamp: datetime = Field(default_factory=datetime.utcnow)

    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat()
        }


class WebSocketMessage(BaseModel):
    """WebSocket message model."""
    action: str
    data: dict = Field(default_factory=dict)

    @classmethod
    def from_event(cls, event: GameEvent) -> 'WebSocketMessage':
        """Create a WebSocket message from a game event."""
        return cls(
            action=event.event_type,
            data=event.dict(exclude={"event_type"})
        )
