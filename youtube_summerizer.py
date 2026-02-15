import os
import asyncio
import tempfile
from typing import Optional
from mcp.server.fastmcp import FastMCP
import subprocess
import json
from openai import OpenAI

# Initialize FastMCP
mcp = FastMCP("YouTube Transcriber")

# Get API key from environment
FIREWORKS_API_KEY = os.environ.get("FIREWORKS_API_KEY")

@mcp.tool()
async def transcribe_youtube(url: str, language: Optional[str] = "en") -> str:
    """
    Transcribes a YouTube video using Fireworks AI Whisper API.
    Extremely fast and accurate. Works for videos without subtitles.
    """
    if not FIREWORKS_API_KEY:
        return "Error: FIREWORKS_API_KEY not found in environment."

    client = OpenAI(
        api_key=FIREWORKS_API_KEY,
        base_url="https://api.fireworks.ai/inference/v1"
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        audio_file = os.path.join(tmpdir, "audio.mp3")
        
        # Download audio using yt-dlp
        print(f"Downloading audio from {url}...")
        try:
            subprocess.run([
                "yt-dlp", 
                "-x", 
                "--audio-format", "mp3", 
                "-o", audio_file, 
                url
            ], check=True, capture_output=True)
        except subprocess.CalledProcessError as e:
            stderr = e.stderr.decode() if e.stderr else "Unknown error"
            return f"Error downloading audio: {stderr}"

        # Transcribe using Fireworks API
        # Using whisper-v3 as it is the most stable and recommended model.
        # whisper-v3-turbo is also available but v3 is standard.
        print("Transcribing via Fireworks AI...")
        try:
            with open(audio_file, "rb") as f:
                transcript = client.audio.transcriptions.create(
                    model="whisper-v3",
                    file=f,
                    language=language,
                    response_format="text"
                )
            return transcript
        except Exception as e:
            return f"Error during transcription: {str(e)}"

if __name__ == "__main__":
    mcp.run()