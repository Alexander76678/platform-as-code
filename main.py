from fastapi import FastAPI
from pymongo import MongoClient
import os
from datetime import datetime

app = FastAPI()

# MongoDB connection (env vars set by Docker later)
MONGO_URI = os.getenv("MONGO_URI", "mongodb://localhost:27017")
client = MongoClient(MONGO_URI)
db = client["platform_db"]
collection = db["visits"]

@app.get("/health")
def health():
    return {"status": "healthy", "timestamp": datetime.utcnow().isoformat()}

@app.get("/visit")
def visit():
    # Write a simple document to MongoDB
    collection.insert_one({"timestamp": datetime.utcnow()})
    count = collection.count_documents({})
    return {"message": "Visit recorded", "total_visits": count}
