// Fernsy demo server: a minimal Xtream Codes API with fictional, freely licensed content,
// for App Review and for trying the app. Runs as a Cloudflare Worker (deploy.sh).
//
// Login: any server URL of this worker, username "demo", password "demo".
// Content language follows the app's Accept-Language (German or English).
// Media files are assets of the GitHub release "demo-media" of obi12341/fernsy.

// Uploaded as a text module (the Workers API has no JSON module type).
import RAW_DATA from "./data.json";
const DATA = JSON.parse(RAW_DATA);

const MEDIA = "https://github.com/obi12341/fernsy/releases/download/demo-media/";
const USER = "demo";
const PASS = "demo";

// "Live" channels play one looped recording. Every request starts where a real live
// channel would be at this moment, and the data is paced at real time (with a small lead,
// like Xtream servers), so the player never has to pause the download and a reconnect
// lands on the current position.
const LIVE = { file: "live.ts", bytes: 195752368, seconds: 659.712 };
const LEAD_SECONDS = 8;      // burst at the start, then real time
const CHUNK_SECONDS = 3;     // one ranged subrequest per chunk
const MAX_CHUNKS = 45;       // free plan: 50 subrequests per request; the player reconnects after ~2 min
const TS_PACKET = 188;

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;
    const lang = (request.headers.get("Accept-Language") || "").toLowerCase().startsWith("de") ? "de" : "en";

    if (path === "/" || path === "") return info(url, lang);
    if (path === "/player_api.php") return api(url, lang);

    const stream = path.match(/^\/(live|movie|series)\/([^/]+)\/([^/]+)\/(\d+)\.(\w+)$/);
    if (stream) {
      const [, kind, user, pass, id] = stream;
      if (decodeURIComponent(user) !== USER || decodeURIComponent(pass) !== PASS) return new Response("Forbidden", { status: 403 });
      if (kind === "live") return live(Number(id));
      return Response.redirect(MEDIA + "movie.mp4", 302);
    }

    const image = path.match(/^\/img\/(de|en)\/([a-z]+_\d+(?:_bg|_e\d)?)\.png$/);
    if (image) {
      const [, imgLang, name] = image;
      const file = name.startsWith("logo_") ? `${imgLang}-${name}.png`
        : /_(bg|e\d)$/.test(name) ? `${name}.jpg`
        : `${imgLang}-${name}.jpg`;
      return Response.redirect(MEDIA + file, 302);
    }
    return new Response("Not found", { status: 404 });
  },
};

function info(url, lang) {
  const text = lang === "de"
    ? `Fernsy-Demoserver\n\nServer: ${url.origin}\nBenutzername: ${USER}\nPasswort: ${PASS}\n\nAlle Inhalte sind erfunden; Videos: Blender Foundation (CC BY).\n`
    : `Fernsy demo server\n\nServer: ${url.origin}\nUsername: ${USER}\nPassword: ${PASS}\n\nAll content is fictional; videos: Blender Foundation (CC BY).\n`;
  return new Response(text, { headers: { "Content-Type": "text/plain; charset=utf-8" } });
}

function live(id) {
  const rate = LIVE.bytes / LIVE.seconds;
  const align = (bytes) => Math.floor(bytes / TS_PACKET) * TS_PACKET;
  const started = Date.now() / 1000;
  // Channels are offset against each other so they do not all show the same scene.
  let position = align(((started + id * 41) % LIVE.seconds) * rate);
  const { readable, writable } = new TransformStream();

  const pump = async () => {
    let sentSeconds = 0;
    try {
      for (let i = 0; i < MAX_CHUNKS; i++) {
        if (position >= LIVE.bytes) position = 0;   // end of the loop: timestamps restart, the player resyncs
        const seconds = i === 0 ? LEAD_SECONDS + CHUNK_SECONDS : CHUNK_SECONDS;
        const end = Math.min(position + align(seconds * rate), LIVE.bytes);
        const upstream = await fetch(MEDIA + LIVE.file, { headers: { Range: `bytes=${position}-${end - 1}` } });
        if (!upstream.ok || !upstream.body) break;
        await upstream.body.pipeTo(writable, { preventClose: true });
        sentSeconds += (end - position) / rate;
        position = end;
        const wait = sentSeconds - LEAD_SECONDS - (Date.now() / 1000 - started);
        if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait * 1000));
      }
      await writable.close();
    } catch {
      // The player went away (channel switch, window closed).
      try { await writable.abort(); } catch {}
    }
  };
  pump();
  return new Response(readable, { status: 200, headers: { "Content-Type": "video/mp2t", "Cache-Control": "no-store" } });
}

function json(value) {
  return new Response(JSON.stringify(value), { headers: { "Content-Type": "application/json; charset=utf-8" } });
}

function api(url, lang) {
  const q = url.searchParams;
  const now = Math.floor(Date.now() / 1000);
  const d = DATA[lang];
  const base = url.origin;
  if (q.get("username") !== USER || q.get("password") !== PASS) {
    return json({ user_info: { auth: 0, status: "Disabled" } });
  }
  switch (q.get("action")) {
    case null:
      return json({
        user_info: { username: USER, password: PASS, auth: 1, status: "Active", exp_date: String(now + 365 * 86400),
                     max_connections: "5", active_cons: "0" },
        server_info: { url: url.hostname, server_protocol: "https" },
      });
    case "get_live_categories": return json(d.liveCats.map(([id, name]) => ({ category_id: id, category_name: name, parent_id: 0 })));
    case "get_vod_categories": return json(d.movieCats.map(([id, name]) => ({ category_id: id, category_name: name, parent_id: 0 })));
    case "get_series_categories": return json(d.seriesCats.map(([id, name]) => ({ category_id: id, category_name: name, parent_id: 0 })));
    case "get_live_streams":
      return json(d.channels.map(([id, name, cat], i) => ({
        num: i + 1, name, stream_type: "live", stream_id: id, stream_icon: `${base}/img/${lang}/logo_${id}.png`,
        epg_channel_id: `demo${id}`, category_id: cat, tv_archive: 0, is_adult: 0,
      })));
    case "get_vod_streams":
      return json(d.movies.map(([name, cat, , , rating], i) => ({
        num: i + 1, name, stream_type: "movie", stream_id: 500 + i, stream_icon: `${base}/img/${lang}/movie_${i}.png`,
        rating: String(rating), added: String(now - i * 3 * 86400), category_id: i >= 6 ? cat : "10",
        container_extension: "mp4", is_adult: 0,
      })));
    case "get_series":
      return json(d.series.map(([name, cat, year, rating, , , plot, genre], i) => ({
        num: i + 1, name, series_id: 800 + i, cover: `${base}/img/${lang}/series_${i}.png`, plot,
        cast: "Lena Albrecht, Jonas Kerber, Mira Sander", genre, releaseDate: `${year}-03-01`, rating: String(rating),
        category_id: cat, last_modified: String(now - i * 86400),
      })));
    case "get_vod_info": {
      const i = Number(q.get("vod_id")) - 500;
      const m = d.movies[i];
      if (!m) return json({ info: {} });
      const [name, cat, year, minutes, rating, , plot] = m;
      const genre = Object.fromEntries(d.movieCats)[cat];
      return json({
        info: { plot, genre, cast: "Lena Albrecht, Jonas Kerber, Mira Sander, Paul Ostendorf", director: "Ruth Weidenfeld",
                releasedate: `${year}-09-12`, duration: `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}:00`,
                rating: String(rating), backdrop_path: [`${base}/img/${lang}/movie_${i}_bg.png`], movie_image: `${base}/img/${lang}/movie_${i}.png` },
        movie_data: { stream_id: 500 + i, name, container_extension: "mp4" },
      });
    }
    case "get_series_info": {
      const i = Number(q.get("series_id")) - 800;
      const s = d.series[i];
      if (!s) return json({ info: {}, episodes: {} });
      const [name, , , , , seasons, plot] = s;
      const episodes = {};
      for (let season = 1; season <= seasons; season++) {
        episodes[String(season)] = Array.from({ length: 8 }, (_, e) => ({
          id: `${i}${String(season).padStart(2, "0")}${String(e).padStart(2, "0")}`, episode_num: e + 1, season,
          title: d.episodeTitles[(e + season * 3) % d.episodeTitles.length], container_extension: "mp4",
          info: { plot: d.episodePlot, duration_secs: 2700 + e * 60, movie_image: `${base}/img/${lang}/series_${i}_e${e % 6}.png` },
        }));
      }
      return json({ info: { name, plot, backdrop_path: [`${base}/img/${lang}/series_${i}_bg.png`] }, episodes });
    }
    case "get_short_epg":
    case "get_simple_data_table": {
      const id = Number(q.get("stream_id"));
      const channel = d.channels.find(([cid]) => cid === id);
      if (!channel) return json({ epg_listings: [] });
      let listings = schedule(id, d.genres[channel[2]], now);
      if (q.get("action") === "get_short_epg") {
        listings = listings.filter((e) => Number(e.stop_timestamp) > now).slice(0, Number(q.get("limit") || 4));
      }
      return json({ epg_listings: listings });
    }
    default:
      return json([]);
  }
}

/// Deterministic programme per channel from six hours ago to three days ahead.
function schedule(id, shows, now) {
  let seed = id >>> 0;
  const random = () => {   // mulberry32
    seed = (seed + 0x6d2b79f5) >>> 0;
    let t = seed;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  // Anchored to the day, so the programme stays the same within a day.
  const day = Math.floor(now / 86400) * 86400;
  let t = day - 86400 + [0, 300, 600, 900][Math.floor(random() * 4)];
  const end = now + 3 * 86400;
  const out = [];
  let n = 0;
  while (t < end) {
    const [title, minutes, description] = shows[Math.floor(random() * shows.length)];
    const stop = t + minutes * 60;
    if (stop > now - 6 * 3600) {
      out.push({ id: String(n), epg_id: String(id), channel_id: `demo${id}`, lang: "de", title: b64(title),
                 description: b64(description), start_timestamp: String(t), stop_timestamp: String(stop) });
    }
    t = stop;
    n++;
  }
  return out;
}

function b64(text) {
  let binary = "";
  for (const byte of new TextEncoder().encode(text)) binary += String.fromCharCode(byte);
  return btoa(binary);
}
