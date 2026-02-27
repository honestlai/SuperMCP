import os, re, base64, subprocess, tempfile
from pathlib import Path
from typing import Optional
from mcp.server.fastmcp import FastMCP
from openai import OpenAI

mcp = FastMCP("Video Doc MCP")

# ── Vision config (OpenAI SDK — works with OpenAI, Ollama, any compat endpoint) ──
def get_vision_client():
    return OpenAI(
        api_key=os.getenv("VISION_API_KEY", "ollama"),
        base_url=os.getenv("VISION_BASE_URL", "http://ollama:11434/v1"),
    )

VISION_MODEL = lambda: os.getenv("VISION_MODEL", "llava")

# ── Transcription config (reuse existing youtube transcriber pattern) ──────────
def get_transcription_client():
    return OpenAI(
        api_key=os.getenv("TRANSCRIBER_API_KEY") or os.getenv("FIREWORKS_API_KEY", ""),
        base_url=os.getenv("TRANSCRIBER_BASE_URL", "https://api.groq.com/openai/v1"),
    )

TRANSCRIPTION_MODEL = lambda: os.getenv("TRANSCRIBER_MODEL", "whisper-large-v3-turbo")

DOC_TYPE_PROMPTS = {
    "meeting": "This is a frame from an internal meeting recording. Describe what's on screen (slides, whiteboard, screen share, chat). Note anything important: decisions, action items, diagrams. Rate importance 1-10 where 10=critical info visible.",
    "discovery": "This is a frame from a client discovery call. Describe what's visible and any requirements, pain points, or key client statements shown. Rate importance 1-10.",
    "howto": "This is a frame from a tutorial/how-to recording. Describe the exact step being demonstrated, any UI, commands, or actions visible. Be precise — this becomes docs. Rate importance 1-10.",
    "general": "Describe what's happening in this video frame. Note any text, diagrams, or important visuals. Rate importance 1-10.",
}

SUMMARY_PROMPTS = {
    "meeting":   "Summarize this meeting transcript. Write: a 3-sentence summary, then 'ACTION ITEMS:' followed by a numbered list of concrete next steps.\n\n",
    "discovery": "Summarize this discovery call. Write: a 3-sentence summary of the prospect's situation, then 'KEY REQUIREMENTS:' followed by a numbered list of needs expressed.\n\n",
    "howto":     "Summarize this tutorial. Write: a 2-sentence overview, then 'STEPS:' followed by a numbered list of the main steps shown.\n\n",
    "general":   "Summarize this video in 3 sentences, then 'KEY POINTS:' as a numbered list.\n\n",
}


def resolve_video(source: str, tmp_dir: str) -> tuple[str, str]:
    """
    Accept a URL or local path. Returns (local_video_path, inferred_title).
    URLs are downloaded via yt-dlp (handles Zoom, Loom, Drive, Vimeo, direct mp4, etc.)
    """
    is_url = re.match(r"^https?://", source.strip())

    if is_url:
        out_path = os.path.join(tmp_dir, "video.%(ext)s")
        # Grab the title before downloading
        title_result = subprocess.run(
            ["yt-dlp", "--print", "title", "--no-playlist", source],
            capture_output=True, text=True, timeout=30,
        )
        title = title_result.stdout.strip() or Path(source).stem

        subprocess.run(
            ["yt-dlp", "-o", out_path, "--no-playlist",
             "-f", "best[ext=mp4]/bestvideo[ext=mp4]+bestaudio/best",
             "--merge-output-format", "mp4", source],
            check=True, capture_output=True, timeout=600,
        )
        matches = list(Path(tmp_dir).glob("video.*"))
        if not matches:
            raise FileNotFoundError(f"yt-dlp downloaded nothing for: {source}")
        return str(matches[0]), title

    else:
        if not os.path.exists(source):
            raise FileNotFoundError(f"Local file not found: {source}")
        title = Path(source).stem.replace("_", " ").replace("-", " ").title()
        return source, title


def extract_audio(video_path: str, out_path: str):
    subprocess.run(
        ["ffmpeg", "-i", video_path, "-vn", "-ar", "16000", "-ac", "1", "-f", "mp3", out_path, "-y"],
        check=True, capture_output=True,
    )


def extract_frames(video_path: str, out_dir: str, max_frames: int = 20) -> list[dict]:
    """Extract keyframes via scene change detection, fall back to interval."""
    scene_pattern = os.path.join(out_dir, "frame_%06d.jpg")
    try:
        subprocess.run(
            ["ffmpeg", "-i", video_path,
             "-vf", "select='gt(scene,0.35)',scale='min(1280,iw)':-2,setpts=N/TB",
             "-vsync", "vfr", "-q:v", "3", scene_pattern, "-y"],
            check=True, capture_output=True, timeout=120,
        )
    except subprocess.CalledProcessError:
        pass

    frames = sorted(Path(out_dir).glob("frame_*.jpg"))

    # Fall back to interval if scene detection found nothing
    if len(frames) < 3:
        result = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "default=noprint_wrappers=1:nokey=1", video_path],
            capture_output=True, text=True,
        )
        duration = float(result.stdout.strip() or "60")
        interval = max(1, int(duration / max_frames))
        interval_pattern = os.path.join(out_dir, "frame_%06d.jpg")
        subprocess.run(
            ["ffmpeg", "-i", video_path, "-vf", f"fps=1/{interval},scale='min(1280,iw)':-2",
             "-q:v", "3", interval_pattern, "-y"],
            check=True, capture_output=True, timeout=120,
        )
        frames = sorted(Path(out_dir).glob("frame_*.jpg"))

    # Cap and space evenly if over max
    if len(frames) > max_frames:
        step = len(frames) // max_frames
        frames = frames[::step][:max_frames]

    result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", video_path],
        capture_output=True, text=True,
    )
    duration = float(result.stdout.strip() or "60")
    return [
        {"path": str(f), "timestamp": round(i * duration / max(len(frames) - 1, 1), 1)}
        for i, f in enumerate(frames)
    ]


def analyze_frame(client: OpenAI, image_path: str, prompt: str) -> tuple[str, int]:
    """Returns (description, importance_score 1-10)."""
    with open(image_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    try:
        resp = client.chat.completions.create(
            model=VISION_MODEL(),
            messages=[{"role": "user", "content": [
                {"type": "text", "text": prompt},
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
            ]}],
            max_tokens=300,
        )
        text = resp.choices[0].message.content or ""
        score = 5
        for word in text.split():
            cleaned = word.strip(".,()[]:")
            if cleaned.isdigit() and 1 <= int(cleaned) <= 10:
                score = int(cleaned)
        return text, score
    except Exception as e:
        return f"[frame analysis unavailable: {e}]", 0


def build_markdown(title, doc_type, summary, action_items, transcript, frames_info) -> str:
    lines = [f"# {title}\n", f"**Type:** {doc_type}\n"]

    lines.append("## Summary\n")
    lines.append(summary.strip() + "\n")

    if action_items:
        label = {"meeting": "Action Items", "discovery": "Key Requirements",
                 "howto": "Steps", "general": "Key Points"}.get(doc_type, "Key Points")
        lines.append(f"\n## {label}\n")
        for i, item in enumerate(action_items, 1):
            lines.append(f"{i}. {item}\n")

    if frames_info:
        lines.append("\n## Screenshots\n")
        for f in frames_info:
            ts = f["timestamp"]
            mins, secs = divmod(int(ts), 60)
            lines.append(f"\n### [{mins:02d}:{secs:02d}] — Importance: {f['score']}/10\n")
            lines.append(f"![frame at {mins:02d}:{secs:02d}]({f['path']})\n")
            lines.append(f"\n{f['description']}\n")

    lines.append("\n## Full Transcript\n")
    lines.append("```\n" + transcript.strip() + "\n```\n")

    return "\n".join(lines)


@mcp.tool()
async def process_video(
    video_source: str,
    doc_type: str = "meeting",
    title: Optional[str] = None,
    max_frames: int = 20,
    min_importance: int = 6,
) -> str:
    """
    Process a video recording into a summary document with embedded screenshots.

    Args:
        video_source:   A streamable URL *or* a local file path.
                        URLs: Zoom cloud recording, Loom, Google Drive share link,
                              Vimeo, direct .mp4 link, or any yt-dlp-supported platform.
                        Local: /workspace/meeting.mp4 (mp4, mov, mkv, webm, avi)
        doc_type:       "meeting" | "discovery" | "howto" | "general"
        title:          Document title (auto-detected from URL/filename if omitted)
        max_frames:     Max frames to analyze (default 20)
        min_importance: Only include frames scoring >= this (default 6, range 1-10)

    Returns:
        Path to generated markdown file in /workspace/outputs/
    """
    doc_type = doc_type.lower()
    if doc_type not in DOC_TYPE_PROMPTS:
        doc_type = "general"

    out_dir = "/workspace/outputs"
    os.makedirs(out_dir, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp:
        # 0. Resolve source → local file (download if URL)
        try:
            video_path, inferred_title = resolve_video(video_source, tmp)
        except Exception as e:
            return f"Error resolving video source: {e}"

        title = title or inferred_title
        safe_stem = re.sub(r"[^\w\-]", "_", title)[:60]
        out_file = os.path.join(out_dir, f"{safe_stem}_{doc_type}.md")

        # 1. Transcribe
        audio_path = os.path.join(tmp, "audio.mp3")
        transcript = ""
        try:
            extract_audio(video_path, audio_path)
            tclient = get_transcription_client()
            with open(audio_path, "rb") as af:
                result = tclient.audio.transcriptions.create(
                    model=TRANSCRIPTION_MODEL(), file=af, response_format="text"
                )
            transcript = str(result)
        except Exception as e:
            transcript = f"[Transcription unavailable: {e}]"

        # 2. Extract frames
        frames = extract_frames(video_path, tmp, max_frames)

        # 3. Analyze frames with vision model
        vclient = get_vision_client()
        frame_prompt = DOC_TYPE_PROMPTS[doc_type]
        analyzed = []
        for frame in frames:
            desc, score = analyze_frame(vclient, frame["path"], frame_prompt)
            if score >= min_importance:
                analyzed.append({**frame, "description": desc, "score": score})

        # 4. Summarize transcript
        summary, action_items = "", []
        try:
            summary_prompt = SUMMARY_PROMPTS[doc_type] + transcript[:8000]
            resp = vclient.chat.completions.create(
                model=VISION_MODEL(),
                messages=[{"role": "user", "content": summary_prompt}],
                max_tokens=600,
            )
            raw = resp.choices[0].message.content or ""
            dividers = ["ACTION ITEMS:", "KEY REQUIREMENTS:", "STEPS:", "KEY POINTS:"]
            split_at = next((d for d in dividers if d in raw.upper()), None)
            if split_at:
                idx = raw.upper().index(split_at)
                summary = raw[:idx].strip()
                items_raw = raw[idx + len(split_at):].strip()
                action_items = [
                    l.lstrip("0123456789.-) ").strip()
                    for l in items_raw.splitlines()
                    if l.strip() and len(l.strip()) > 3
                ]
            else:
                summary = raw.strip()
        except Exception as e:
            summary = f"[Summary unavailable: {e}]"

        # 5. Build and write document
        md = build_markdown(title, doc_type, summary, action_items, transcript, analyzed)
        with open(out_file, "w") as f:
            f.write(md)

    return f"Done. Document saved to {out_file} ({len(analyzed)} screenshots included)"


@mcp.tool()
def video_doc_config() -> dict:
    """Show current video-doc-mcp configuration."""
    return {
        "vision_base_url": os.getenv("VISION_BASE_URL", "http://ollama:11434/v1"),
        "vision_model": os.getenv("VISION_MODEL", "llava"),
        "transcription_model": os.getenv("TRANSCRIBER_MODEL", "whisper-large-v3-turbo"),
        "video_input": "URL (Zoom, Loom, Drive, direct mp4, etc.) or /workspace local path",
        "doc_output": "/workspace/outputs/",
        "supported_doc_types": ["meeting", "discovery", "howto", "general"],
        "url_support": "Any platform supported by yt-dlp (500+ sites)",
    }


if __name__ == "__main__":
    mcp.run()
