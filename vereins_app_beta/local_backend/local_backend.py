import os
import uuid
import base64
from datetime import datetime
from flask import send_from_directory
from flask import Flask, request, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)  # Für Cross-Origin Requests von Flutter lokal

# Statische Mitgliederliste (Beispiel)
members = [
    {"id": "1", "name": "Max Mustermann"},
    {"id": "2", "name": "Der Spiess"},
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

# In-memory Storage für Fotos
UPLOAD_FOLDER = 'uploaded_photos'
#photos = [{'id': 'p2', 'filename': 'xyz.jpg'}]
photos = [{'id': f, 'filename': f} for f in os.listdir(UPLOAD_FOLDER)]


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


@app.route('/fines/<fine_id>', methods=['DELETE'])
def delete_fine(fine_id):
    found = False
    for member_id, member_fines in fines.items():
        for fine in member_fines:
            if fine['id'] == fine_id:
                member_fines.remove(fine)
                found = True
                print(f"Strafe {fine_id} gelöscht für Mitglied {member_id}")
                return jsonify({'message': f'Strafe {fine_id} gelöscht'}), 200

    if not found:
        return jsonify({'error': 'Strafe nicht gefunden'}), 404


# Speicherordner für Fotos
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# --- FOTO APIs ---

@app.route('/photos', methods=['GET'])
def get_photos():
    # Gibt Liste aller Fotos zurück mit URL
    result = []
    for photo in photos:
        result.append({
            'id': photo['id'],
            'url': request.host_url + 'photos/' + photo['filename']
        })
    return jsonify(result)


@app.route('/photos', methods=['POST'])
def upload_photo():
    data = request.get_json()
    image_b64 = data.get('imageBase64')

    if not image_b64:
        return jsonify({'error': 'Kein Bild gesendet'}), 400

    try:
        # Base64 zu Bytes dekodieren
        image_data = base64.b64decode(image_b64)

        # Eindeutigen Dateinamen erzeugen
        now = datetime.now()
        filename = f'{now.strftime("%Y%m%d-%H%M%S")}{int(now.microsecond / 1000):03d}.jpg'

        # Datei speichern
        filepath = os.path.join(UPLOAD_FOLDER, filename)
        with open(filepath, 'wb') as f:
            f.write(image_data)

        # Foto registrieren
        photo_id = uuid.uuid4().hex
        photos.append({'id': photo_id, 'filename': filename})

        return jsonify({'id': photo_id, 'url': request.host_url + 'photos/' + filename})

    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/photos/<filename>', methods=['GET'])
def serve_photo(filename):
    # Liefert lokale Foto-Datei aus
    return send_from_directory(UPLOAD_FOLDER, filename)


@app.route('/photos/<photo_id>', methods=['DELETE'])
def delete_photo(photo_id):
    global photos
    # Foto mit photo_id finden
    photo = next((p for p in photos if p['id'] == photo_id), None)
    if not photo:
        return jsonify({'error': 'Foto nicht gefunden'}), 404

    try:
        # Datei löschen
        filepath = os.path.join(UPLOAD_FOLDER, photo['filename'])
        if os.path.exists(filepath):
            os.remove(filepath)

        # Foto aus Liste entfernen
        photos = [p for p in photos if p['id'] != photo_id]

        return jsonify({'message': 'Foto gelöscht'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500



if __name__ == '__main__':
    app.run(debug=True, port=5000)
