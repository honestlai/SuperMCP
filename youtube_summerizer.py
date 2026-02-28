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

# ── Provider presets ─────────────────────────────────────────────────────────
# Each preset defines a base_url and default model for a known provider.
# Users can override any of these with TRANSCRIBER_BASE_URL / TRANSCRIBER_MODEL.
PROVIDER_PRESETS = {
    "openai": {
        "base_url": "https://api.openai.com/v1",
        "model": "whisper-1",
    },
    "fireworks": {
        "base_url": "https://api.fireworks.ai/inference/v1",
        "model": "whisper-v3",
    },
    "groq": {
        "base_url": "https://api.groq.com/openai/v1",
        "model": "whisper-large-v3-turbo",
    },
}

# ── Resolve configuration from environment ───────────────────────────────────
def get_config():
    """
    Resolve transcription provider settings from environment variables.

    Priority:
      1. Explicit overrides:  TRANSCRIBER_BASE_URL / TRANSCRIBER_MODEL
      2. Provider preset:     TRANSCRIBER_PROVIDER  (openai | fireworks | groq)
      3. Unified fallback:    LLM_API_KEY / LLM_BASE_URL  (shared provider)
      4. Legacy fallback:     FIREWORKS_API_KEY  (auto-selects fireworks preset)

    At minimum, an API key must be set via TRANSCRIBER_API_KEY, LLM_API_KEY,
    or legacy FIREWORKS_API_KEY.
    """
    provider = os.environ.get("TRANSCRIBER_PROVIDER", "").lower().strip()
    api_key = (os.environ.get("TRANSCRIBER_API_KEY") or
               os.environ.get("FIREWORKS_API_KEY") or
               os.environ.get("LLM_API_KEY"))
    base_url = os.environ.get("TRANSCRIBER_BASE_URL")
    model = os.environ.get("TRANSCRIBER_MODEL")

    # Infer provider from explicit keys or unified LLM_BASE_URL
    if not provider and not base_url:
        if os.environ.get("FIREWORKS_API_KEY") and not os.environ.get("TRANSCRIBER_API_KEY"):
            provider = "fireworks"
        else:
            # Auto-detect from LLM_BASE_URL so the right default model is applied
            llm_url = os.environ.get("LLM_BASE_URL", "")
            if "fireworks.ai" in llm_url:
                provider = "fireworks"
            elif "groq.com" in llm_url:
                provider = "groq"
            elif "openai.com" in llm_url:
                provider = "openai"

    # Apply preset defaults — explicit TRANSCRIBER_MODEL still overrides
    if provider in PROVIDER_PRESETS:
        preset = PROVIDER_PRESETS[provider]
        base_url = base_url or preset["base_url"]
        model = model or preset["model"]

    # Fall back to unified LLM_BASE_URL if no service-specific URL was set
    base_url = base_url or os.environ.get("LLM_BASE_URL") or "https://api.openai.com/v1"
    model = model or "whisper-1"

    return {
        "api_key": api_key,
        "base_url": base_url,
        "model": model,
        "provider": provider or "custom",
    }


@mcp.tool()
async def transcribe_youtube(url: str, language: Optional[str] = "en") -> str:
    """
    Transcribes a YouTube video using a Whisper-compatible speech-to-text API.

    Supports multiple providers via environment variables:
      - OpenAI (whisper-1)
      - Fireworks AI (whisper-v3)
      - Groq (whisper-large-v3-turbo)
      - Any OpenAI-compatible endpoint

    Set TRANSCRIBER_PROVIDER to 'openai', 'fireworks', or 'groq' for easy setup,
    or use TRANSCRIBER_BASE_URL and TRANSCRIBER_MODEL for full control.
    """
    config = get_config()

    if not config["api_key"]:
        return (
            "Error: No API key found. Set LLM_API_KEY (unified), TRANSCRIBER_API_KEY, "
            "or legacy FIREWORKS_API_KEY in your environment variables."
        )

    client = OpenAI(
        api_key=config["api_key"],
        base_url=config["base_url"],
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        audio_file = os.path.join(tmpdir, "audio.mp3")

        # Download audio using yt-dlp
        print(f"Downloading audio from {url}...")
        try:
            subprocess.run(
                ["yt-dlp", "-x", "--audio-format", "mp3", "-o", audio_file, url],
                check=True,
                capture_output=True,
            )
        except subprocess.CalledProcessError as e:
            stderr = e.stderr.decode() if e.stderr else "Unknown error"
            return f"Error downloading audio: {stderr}"

        # Transcribe using the configured provider
        print(f"Transcribing via {config['provider']} ({config['model']})...")
        try:
            with open(audio_file, "rb") as f:
                transcript = client.audio.transcriptions.create(
                    model=config["model"],
                    file=f,
                    language=language,
                    response_format="text",
                )
            return transcript
        except Exception as e:
            return f"Error during transcription: {str(e)}"


if __name__ == "__main__":
    mcp.run()
