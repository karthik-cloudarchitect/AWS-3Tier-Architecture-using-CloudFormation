from flask import Flask
import mysql.connector
import os

app = Flask(__name__)

# These should be moved to environment variables in production
RDS_HOST = os.environ.get("RDS_HOST", "your-db-endpoint.rds.amazonaws.com")
RDS_PORT = 3306
RDS_USER = "admin"
RDS_PASS = "MyDBPass123!"
RDS_DB = "testdb"

@app.route("/")
def home():
    try:
        conn = mysql.connector.connect(
            host=RDS_HOST,
            user=RDS_USER,
            password=RDS_PASS,
            port=RDS_PORT
        )
        return "✅ Connected to RDS MySQL instance"
    except Exception as e:
        return f"⚠️ Backend is running but RDS connection failed: {str(e)[:50]}..."

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)

