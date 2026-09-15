import { useCallback, useEffect, useState } from "react";
import ShipViewer from "./ShipViewer";
import { SHIPS } from "./ships";

const STORE_KEY = "hyperdrift.ship";

function loadShip(): number {
  try {
    const v = Number(localStorage.getItem(STORE_KEY));
    return v === 1 ? 1 : 0;
  } catch {
    return 0;
  }
}

export default function App() {
  const [shipId, setShipId] = useState<number>(() => loadShip());
  const [selectedId, setSelectedId] = useState<number>(() => loadShip());
  const [autoRotate, setAutoRotate] = useState(true);
  const [showFlares, setShowFlares] = useState(true);
  const [musicSim, setMusicSim] = useState(true);
  const [toast, setToast] = useState("");

  const cycle = useCallback((dir: number) => {
    setShipId((id) => (id + dir + SHIPS.length) % SHIPS.length);
  }, []);

  const select = useCallback(() => {
    setSelectedId(shipId);
    try {
      localStorage.setItem(STORE_KEY, String(shipId));
    } catch {
      /* storage unavailable */
    }
    setToast(`${SHIPS[shipId].name} SELECTED`);
  }, [shipId]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "ArrowLeft") cycle(-1);
      else if (e.key === "ArrowRight") cycle(1);
      else if (e.key === "Enter") select();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [cycle, select]);

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(""), 1800);
    return () => clearTimeout(t);
  }, [toast]);

  const ship = SHIPS[shipId];

  return (
    <div className="hangar">
      <header className="hangar-head">
        <div>
          <h1>
            HYPERDRIFT <span>HANGAR</span>
          </h1>
          <p className="sub">LIVE SHIP SELECT PREVIEW — GEOMETRY MIRRORED FROM THE GODOT BUILD</p>
        </div>
        <div className="head-chip">
          <span className="dot" />
          {SHIPS[selectedId].name} EQUIPPED
        </div>
      </header>

      <main className="hangar-main">
        <section className="stage">
          <ShipViewer
            shipId={shipId}
            autoRotate={autoRotate}
            showFlares={showFlares}
            musicSim={musicSim}
          />
          <div className="stage-bar">
            <button className="btn ghost" onClick={() => cycle(-1)} aria-label="Previous ship">
              ◀
            </button>
            <button className="btn primary" onClick={select}>
              SELECT {ship.name}
            </button>
            <button className="btn ghost" onClick={() => cycle(1)} aria-label="Next ship">
              ▶
            </button>
          </div>
          <div className="toggles">
            <label>
              <input
                type="checkbox"
                checked={autoRotate}
                onChange={(e) => setAutoRotate(e.target.checked)}
              />
              TURNTABLE
            </label>
            <label>
              <input
                type="checkbox"
                checked={showFlares}
                onChange={(e) => setShowFlares(e.target.checked)}
              />
              MUSIC FLARES
            </label>
            <label>
              <input
                type="checkbox"
                checked={musicSim}
                onChange={(e) => setMusicSim(e.target.checked)}
              />
              124 BPM SIM
            </label>
          </div>
        </section>

        <aside className="ships">
          {SHIPS.map((s) => {
            const active = s.id === shipId;
            const equipped = s.id === selectedId;
            return (
              <article
                key={s.id}
                className={`card${active ? " active" : ""}`}
                style={{ ["--accent" as string]: s.accent }}
                onClick={() => setShipId(s.id)}
              >
                <div className="card-top">
                  <h2>{s.name}</h2>
                  {equipped && <span className="equipped">EQUIPPED</span>}
                </div>
                <p className="tagline">{s.tagline}</p>
                <p className="desc">{s.desc}</p>
                <dl className="specs">
                  {s.specs.map(([k, v]) => (
                    <div key={k}>
                      <dt>{k}</dt>
                      <dd>{v}</dd>
                    </div>
                  ))}
                </dl>
                <button
                  className={`btn small${active ? " primary" : " ghost"}`}
                  onClick={(e) => {
                    e.stopPropagation();
                    setShipId(s.id);
                    setSelectedId(s.id);
                    try {
                      localStorage.setItem(STORE_KEY, String(s.id));
                    } catch {
                      /* storage unavailable */
                    }
                    setToast(`${s.name} SELECTED`);
                  }}
                >
                  {equipped ? "EQUIPPED" : `SELECT ${s.name}`}
                </button>
              </article>
            );
          })}

          <footer className="parity">
            <h3>GODOT PARITY</h3>
            <p>
              Same primitives, sizes, positions and palette as{" "}
              <code>hyperdrift/scripts/ship_factory.gd</code>. In-game: title →{" "}
              <b>HANGAR</b> (or <b>H</b>), or <b>SETTINGS → HANGAR</b> for the live
              turntable. Ships share identical collision + handling.
            </p>
          </footer>
        </aside>
      </main>

      {toast && <div className="toast">{toast}</div>}
    </div>
  );
}
