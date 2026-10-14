// The length of an audio or video, as HH:MM:SS, for the editor's
// duration field and the Posts list's background fill.
//
// A file of ours is read in the browser: a hidden <audio>/<video> loads
// just its metadata. A link to a video elsewhere (YouTube) can't be read
// that way, so the server looks it up — /admin/medium/duration, which asks
// VideoEmbed. Any http(s) link that isn't an audio/video file goes there,
// and the server says whether it knows the service; the list of services
// lives in one place, VideoEmbed::PROVIDERS.
//
// Resolves to "HH:MM:SS", or rejects when there's nothing to read.

const AUDIO = ["mp3", "m4a", "wav", "ogg", "flac", "aac"];
const VIDEO = ["mp4", "webm", "ogv", "mov", "avi", "mkv"];

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

export async function mediaDuration(path) {
  const ext = extension(path);
  const isAudio = AUDIO.includes(ext);
  const isVideo = VIDEO.includes(ext);

  if (!isAudio && !isVideo) {
    if (!/^https?:\/\//i.test(path)) throw new Error("not an audio or video file");
    const response = await fetch(`/admin/medium/duration?path=${encodeURIComponent(path)}`, {
      headers: { Accept: "application/json" },
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok || !data.duration) throw new Error(data.error || "no duration");
    return data.duration;
  }

  const el = isAudio ? new Audio() : document.createElement("video");
  el.preload = "metadata";
  const seconds = await new Promise((resolve, reject) => {
    el.addEventListener("loadedmetadata", () => resolve(el.duration));
    el.addEventListener("error", () => reject(new Error("media load failed")));
    el.src = path;
    el.load();
  });
  if (!isFinite(seconds) || seconds <= 0) throw new Error("no duration");
  return formatDuration(seconds);
}
