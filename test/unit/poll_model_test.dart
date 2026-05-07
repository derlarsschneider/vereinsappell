import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/models/poll.dart';

void main() {
  group('PollOption.fromMap', () {
    test('parses text', () {
      final opt = PollOption.fromMap('opt1', {'text': 'Option A'});
      expect(opt.id, 'opt1');
      expect(opt.text, 'Option A');
    });

    test('toMap round-trips text', () {
      expect(PollOption(id: 'o1', text: 'Ja').toMap(), {'text': 'Ja'});
    });
  });

  group('PollVote.fromMap', () {
    test('parses selections map', () {
      final vote = PollVote.fromMap('member-1', {
        'selections': {'opt1': true, 'opt2': true},
        'updatedAt': 1000,
      });
      expect(vote.memberId, 'member-1');
      expect(vote.selectedOptionIds, containsAll(['opt1', 'opt2']));
      expect(vote.updatedAt, 1000);
    });

    test('handles missing selections', () {
      final vote = PollVote.fromMap('member-1', {'updatedAt': 0});
      expect(vote.selectedOptionIds, isEmpty);
    });
  });

  group('Poll.fromSnapshot', () {
    test('parses full poll', () {
      final poll = Poll.fromSnapshot('poll-1', {
        'title': 'Test Abstimmung',
        'description': 'Beschreibung',
        'allowMultiple': true,
        'isActive': true,
        'isVisible': true,
        'isSecretBallot': false,
        'authorId': 'author-1',
        'createdAt': 2000,
        'options': {
          'opt1': {'text': 'Ja'},
          'opt2': {'text': 'Nein'},
        },
        'votes': {
          'member-1': {
            'selections': {'opt1': true},
            'updatedAt': 3000,
          },
        },
      });
      expect(poll.id, 'poll-1');
      expect(poll.title, 'Test Abstimmung');
      expect(poll.allowMultiple, true);
      expect(poll.options.length, 2);
      expect(poll.votes.length, 1);
      expect(poll.votes['member-1']!.selectedOptionIds, contains('opt1'));
    });

    test('parses poll with no options or votes', () {
      final poll = Poll.fromSnapshot('p', {
        'title': 'Minimal',
        'description': '',
        'allowMultiple': false,
        'isActive': false,
        'isVisible': true,
        'isSecretBallot': false,
        'authorId': 'a',
        'createdAt': 0,
      });
      expect(poll.options, isEmpty);
      expect(poll.votes, isEmpty);
    });
  });

  group('Poll helpers', () {
    Poll buildPoll({bool isSecretBallot = false, bool isActive = true}) {
      return Poll(
        id: 'p1',
        title: 'T',
        description: '',
        options: [
          PollOption(id: 'o1', text: 'A'),
          PollOption(id: 'o2', text: 'B'),
        ],
        allowMultiple: false,
        isActive: isActive,
        isVisible: true,
        isSecretBallot: isSecretBallot,
        authorId: 'auth',
        createdAt: 0,
        votes: {
          'm1': PollVote(memberId: 'm1', selectedOptionIds: ['o1'], updatedAt: 0),
          'm2': PollVote(memberId: 'm2', selectedOptionIds: ['o2'], updatedAt: 0),
        },
      );
    }

    test('countForOption returns correct count', () {
      final poll = buildPoll();
      expect(poll.countForOption('o1'), 1);
      expect(poll.countForOption('o2'), 1);
      expect(poll.countForOption('o3'), 0);
    });

    test('showResults: non-secret always shows', () {
      expect(buildPoll(isSecretBallot: false, isActive: true).showResults, true);
    });

    test('showResults: secret ballot hides while active', () {
      expect(buildPoll(isSecretBallot: true, isActive: true).showResults, false);
    });

    test('showResults: secret ballot shows when inactive', () {
      expect(buildPoll(isSecretBallot: true, isActive: false).showResults, true);
    });
  });
}
