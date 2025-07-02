from flask import Flask, request, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)  # Für Cross-Origin Requests von Flutter lokal

# Statische Mitgliederliste (Beispiel)
members = [
    {"id": "1", "name": "Max Mustermann"},
    {"id": "2", "name": "Anna Beispiel"},
    {"id": "3", "name": "Peter Pan"},
]

# In-Memory-Strafgelder: Dict memberId -> List von Strafen
fines = {
    "1": [{"id": "f1", "reason": "Verspätung", "amount": 5}],
    "2": [],
    "3": [],
}

# Hilfsfunktion für neue ID (einfach hochzählen)
fine_id_counter = 2


@app.route('/members', methods=['GET'])
def get_members():
    return jsonify(members)


@app.route('/fines', methods=['GET'])
def get_fines():
    member_id = request.args.get('memberId')
    if not member_id:
        return jsonify({"error": "memberId fehlt"}), 400

    member_fines = fines.get(member_id, [])
    return jsonify(member_fines)


@app.route('/fines', methods=['POST'])
def add_fine():
    global fine_id_counter
    data = request.json
    member_id = data.get('memberId')
    reason = data.get('reason')
    amount = data.get('amount')

    if not member_id or not reason or amount is None:
        return jsonify({"error": "memberId, reason und amount sind erforderlich"}), 400

    fine_id_counter += 1
    new_fine = {
        "id": f"f{fine_id_counter}",
        "reason": reason,
        "amount": amount,
    }
    fines.setdefault(member_id, []).append(new_fine)

    # Simuliere Push Notification (einfaches Logging)
    print(f"Push-Notification an Mitglied {member_id}: Neue Strafe '{reason}' über {amount}€")

    return jsonify(new_fine), 200


if __name__ == '__main__':
    app.run(debug=True, port=5000)
