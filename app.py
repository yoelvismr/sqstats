from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/')
def hello():
    return jsonify({
        "message": "¡Mi API Flask funciona! 🚀",
        "author": "Yoelvis Mariné Ramos",
        "github": "yoelvismr"
    })

@app.route('/api/health')
def health_check():
    return jsonify({"status": "healthy"})

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)
