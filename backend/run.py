"""Arranca la API:   python run.py
host="0.0.0.0" permite que tu celular (en la misma red Wi-Fi) entre a la API
usando la IP de tu computadora, por ejemplo http://192.168.1.50:5000
"""
from app import create_app

app = create_app()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)