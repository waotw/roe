// The length of an audio or video, as HH:MM:SS, for the editor's
// duration field and the publish modal.
//
// The server reads it (/admin/medium/duration → MediaDurationExtractor):
// a file of ours from its own header (WahWah for audio, ffprobe for
// video), a YouTube link from YouTube. That's exact and the same in every
// browser. Only when the server can't — a link to a file on another site,
// or a file it can't read — does the browser try: a hidden <audio>/<video>
// loads just the metadata.
//
// Content → Global → "Automatically add audio and video duration" decides
// who fills the field. On, the editor fills it whenever the media changes
// (mediaDuration); off, nothing fills it unless the writer presses ADD
// DURATION (detectDuration, duration_detect_controller.js).

const AUDIO = ["mp3", "m4a", "wav", "ogg", "oga", "opus", "flac", "aac"];
const VIDEO = ["mp4", "webm", "ogv", "mov", "m4v", "avi", "mkv"];

function extension(path) {
  const clean = path.split(/[?#]/)[0];
  const dot = clean.lastIndexOf(".");
  return dot === -1 ? "" : clean.slice(dot + 1).toLowerCase();
}

export function formatDuration(seconds) {
  const s = Math.floor(seconds);
  const h = String(Math.floor(s / 3600)).padStart(2, "0");
  const m = String(Math.floor((s % 3600) / 60)).padStart(2, "0");
  const sec = String(s % 60).padStart(2, "0");
  return `${h}:${m}:${sec}`;
}

// The setting, from <meta name="roe-auto-duration"> in the admin layouts.
// Missing reads as on, as the setting does.
export function autoDurationOn() {
  const meta = document.querySelector('meta[name="roe-auto-duration"]');
  return meta?.content !== "off";
}

async function fromServer(path) {
  const response = await fetch(
    `/admin/medium/duration?path=${encodeURIComponent(path)}`,
    { headers: { Accept: "application/json" } },
  );
  const data = await response.json().catch(() => ({}));
  if (!response.ok || !data.duration) {
    const error = new Error(data.error || "no duration");
    error.status = response.status;
    throw error;
  }
  return data.duration;
}

// How long the browser gets to read a length. A hidden <audio>/<video>
// that can't load its file doesn't always say so — in Chrome a missing
// file can leave it waiting with no error at all — so it gets a limit.
const BROWSER_TIMEOUT_MS = 15000;

async function fromBrowser(path, isAudio) {
  const el = isAudio ? new Audio() : document.createElement("video");
  el.preload = "metadata";
  let timer;
  try {
    const seconds = await new Promise((resolve, reject) => {
      timer = setTimeout(() => reject(new Error("timed out")), BROWSER_TIMEOUT_MS);
      el.addEventListener("loadedmetadata", () => resolve(el.duration));
      el.addEventListener("error", () => reject(new Error("media load failed")));
      el.src = path;
      el.load();
    });
    if (!isFinite(seconds) || seconds <= 0) throw new Error("no duration");
    return formatDuration(seconds);
  } finally {
    clearTimeout(timer);
    el.removeAttribute("src");
    el.load();
  }
}

// Read the length now, whatever the setting. Rejects when nothing can.
export async function detectDuration(path) {
  path = (path || "").trim();
  if (!path) throw new Error("no audio or video file");

  const ext = extension(path);
  const isAudio = AUDIO.includes(ext);
  const isMedia = isAudio || VIDEO.includes(ext);
  const ours = path.startsWith("/media/");
  const link = /^https?:\/\//i.test(path);

  // Our files, and links the server may know (YouTube): ask the server.
  if (ours || (link && !isMedia)) {
    try {
      return await fromServer(path);
    } catch (error) {
      // Not a media file, or one of ours that isn't there: nothing for the
      // browser to find either.
      if (!isMedia || error.status === 404) throw error;
    }
  } else if (!isMedia) {
    throw new Error("not an audio or video file");
  }

  // A file the server couldn't read, or a file somewhere else.
  return fromBrowser(path, isAudio);
}

// The automatic fill: only when Roe is set to handle durations.
export async function mediaDuration(path) {
  if (!autoDurationOn()) throw new Error("automatic duration is off");
  return detectDuration(path);
}
