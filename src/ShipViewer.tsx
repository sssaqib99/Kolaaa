import { useEffect, useRef } from "react";
import * as THREE from "three";
import { FLARE_LAYOUT, SHIPS } from "./ships";

export interface HangarSettings {
  shipId: number;
  autoRotate: boolean;
  showFlares: boolean;
  musicSim: boolean;
}

interface Props extends HangarSettings {
  height?: number;
}

const DEG = Math.PI / 180;
const TARGET = new THREE.Vector3(0, 0.75, 0.2);
const BASE_CAM = new THREE.Vector3(4.4, 2.5, 5.6);

function buildMaterials(): Record<string, THREE.Material> {
  const std = (o: THREE.MeshStandardMaterialParameters) =>
    new THREE.MeshStandardMaterial(o);
  const basic = (color: string) => new THREE.MeshBasicMaterial({ color });
  return {
    hullV: std({ color: "#121421", metalness: 0.95, roughness: 0.17 }),
    accentV: std({
      color: "#08080f", metalness: 1.0, roughness: 0.12,
      emissive: "#ff299e", emissiveIntensity: 2.6,
    }),
    trimV: std({
      color: "#050d12", metalness: 1.0, roughness: 0.1,
      emissive: "#2ef2ff", emissiveIntensity: 3.2,
    }),
    glassV: std({
      color: "#59f2ff", emissive: "#59f2ff", emissiveIntensity: 2.2,
      transparent: true, opacity: 0.55, metalness: 0.1, roughness: 0.05,
    }),
    glowCyan: basic("#2ef2ff"),
    glowCyanSoft: basic("#29d8f0"),
    hullP: std({
      color: "#050713", metalness: 0.95, roughness: 0.16,
      emissive: "#060f2e", emissiveIntensity: 0.45,
    }),
    chromeP: std({
      color: "#455799", metalness: 1.0, roughness: 0.16,
      emissive: "#3d85ff", emissiveIntensity: 1.0,
    }),
    violetP: std({
      color: "#140626", metalness: 0.95, roughness: 0.18,
      emissive: "#a333ff", emissiveIntensity: 2.2,
    }),
    glassP: std({
      color: "#3d94eb", emissive: "#3d94eb", emissiveIntensity: 1.5,
      transparent: true, opacity: 0.52, metalness: 0.1, roughness: 0.05,
    }),
    glowViolet: basic("#9e5cff"),
    stageDisc: std({
      color: "#05050d", metalness: 0.6, roughness: 0.45,
      emissive: "#0d1a38", emissiveIntensity: 0.5,
    }),
    ringA: basic("#2ef2ff"),
    ringB: basic("#ff299e"),
  };
}

function buildPartGeometry(
  kind: string,
  size: number[],
): THREE.BufferGeometry {
  switch (kind) {
    case "box":
      return new THREE.BoxGeometry(size[0], size[1], size[2]);
    case "cyl":
      return new THREE.CylinderGeometry(size[0], size[1], size[2], size[3]);
    case "sphere":
      return new THREE.SphereGeometry(size[0], 14, 10);
    case "torus": {
      const [inner, outer, rings, tube] = size;
      return new THREE.TorusGeometry((inner + outer) / 2, (outer - inner) / 2, tube, rings);
    }
    default:
      return new THREE.BoxGeometry(1, 1, 1);
  }
}

/** White flare stamp per style; tinted at runtime like music_flare.gdshader. */
function flareTexture(style: number): THREE.CanvasTexture {
  const S = 128;
  const c = document.createElement("canvas");
  c.width = S;
  c.height = S;
  const g = c.getContext("2d")!;
  g.globalCompositeOperation = "lighter";
  const cx = S / 2;
  const cy = S / 2;
  const radial = (r: number, a: number) => {
    const grad = g.createRadialGradient(cx, cy, 0, cx, cy, r);
    grad.addColorStop(0, `rgba(255,255,255,${a})`);
    grad.addColorStop(1, "rgba(255,255,255,0)");
    g.fillStyle = grad;
    g.fillRect(0, 0, S, S);
  };
  const line = (x0: number, y0: number, x1: number, y1: number, w: number, a: number) => {
    g.strokeStyle = `rgba(255,255,255,${a})`;
    g.lineWidth = w;
    g.beginPath();
    g.moveTo(x0, y0);
    g.lineTo(x1, y1);
    g.stroke();
  };
  if (style === 0) {
    radial(62, 0.9);
    line(cx, 4, cx, S - 4, 3, 0.5);
    line(4, cy, S - 4, cy, 3, 0.5);
  } else if (style === 1) {
    radial(40, 0.55);
    const grad = g.createLinearGradient(0, cy, S, cy);
    grad.addColorStop(0, "rgba(255,255,255,0)");
    grad.addColorStop(0.5, "rgba(255,255,255,0.85)");
    grad.addColorStop(1, "rgba(255,255,255,0)");
    g.fillStyle = grad;
    g.fillRect(0, cy - 5, S, 10);
  } else if (style === 2) {
    radial(34, 0.5);
    line(14, 14, S - 14, S - 14, 3, 0.55);
    line(S - 14, 14, 14, S - 14, 3, 0.55);
    g.strokeStyle = "rgba(255,255,255,0.5)";
    g.lineWidth = 3;
    g.beginPath();
    g.arc(cx, cy, 30, 0, Math.PI * 2);
    g.stroke();
  } else {
    radial(52, 0.7);
    line(cx, 6, cx, S - 6, 2, 0.35);
    line(6, cy, S - 6, cy, 2, 0.35);
    line(20, 20, S - 20, S - 20, 2, 0.3);
    line(S - 20, 20, 20, S - 20, 2, 0.3);
  }
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

const PALETTE: Record<string, THREE.Color> = {
  BASS: new THREE.Color(1.0, 0.34, 0.18),
  DRONE: new THREE.Color(0.48, 0.32, 1.0),
  MELODY: new THREE.Color(0.28, 0.92, 1.0),
  PERCUSSION: new THREE.Color(1.0, 0.82, 0.38),
};

export default function ShipViewer(props: Props) {
  const mountRef = useRef<HTMLDivElement>(null);
  const layerRef = useRef<HTMLSpanElement>(null);
  const barsRef = useRef<HTMLDivElement>(null);
  const settings = useRef<HangarSettings>({
    shipId: props.shipId,
    autoRotate: props.autoRotate,
    showFlares: props.showFlares,
    musicSim: props.musicSim,
  });
  settings.current = {
    shipId: props.shipId,
    autoRotate: props.autoRotate,
    showFlares: props.showFlares,
    musicSim: props.musicSim,
  };

  useEffect(() => {
    const mount = mountRef.current;
    if (!mount) return;

    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.1;
    mount.appendChild(renderer.domElement);

    const scene = new THREE.Scene();
    scene.fog = new THREE.FogExp2(0x05030f, 0.012);

    const camera = new THREE.PerspectiveCamera(42, 1, 0.05, 200);
    const offset = BASE_CAM.clone().sub(TARGET);
    const baseRadius = offset.length();
    let radius = baseRadius;
    let theta = Math.atan2(offset.x, offset.z);
    let phi = Math.acos(THREE.MathUtils.clamp(offset.y / baseRadius, -1, 1));
    const applyCamera = () => {
      const sp = Math.sin(phi);
      camera.position.set(
        TARGET.x + radius * sp * Math.sin(theta),
        TARGET.y + radius * Math.cos(phi),
        TARGET.z + radius * sp * Math.cos(theta),
      );
      camera.lookAt(TARGET);
    };
    applyCamera();

    // ---- lights (mirror ship_preview.gd stage) ----
    scene.add(new THREE.HemisphereLight(0x616bb8, 0x0a0618, 0.9));
    scene.add(new THREE.AmbientLight(0xffffff, 0.25));
    const key = new THREE.DirectionalLight(0xd9e0ff, 2.0);
    key.position.set(4, 8, 3);
    scene.add(key);
    const fill = new THREE.PointLight(0x59bfff, 12, 14, 1.8);
    fill.position.set(-4.5, 2.5, 3.5);
    scene.add(fill);
    const rim = new THREE.PointLight(0xff4db3, 18, 16, 1.8);
    rim.position.set(3.5, 1.6, -4.5);
    scene.add(rim);

    const mats = buildMaterials();

    // ---- stage ----
    const disc = new THREE.Mesh(new THREE.CylinderGeometry(5.4, 5.6, 0.14, 48), mats.stageDisc);
    disc.position.y = -0.07;
    scene.add(disc);
    const ringA = new THREE.Mesh(new THREE.TorusGeometry(3.115, 0.065, 8, 64), mats.ringA);
    ringA.rotation.x = Math.PI / 2;
    ringA.position.y = 0.02;
    scene.add(ringA);
    const ringB = new THREE.Mesh(new THREE.TorusGeometry(4.395, 0.045, 8, 72), mats.ringB);
    ringB.rotation.x = Math.PI / 2;
    ringB.position.y = 0.02;
    scene.add(ringB);

    // ---- ships ----
    const turntable = new THREE.Group();
    turntable.position.y = 1.2;
    turntable.rotation.y = -0.55;
    scene.add(turntable);

    const models: THREE.Group[] = [];
    const glowSets: THREE.Object3D[][] = [];
    SHIPS.forEach((def) => {
      const root = new THREE.Group();
      const glows: THREE.Object3D[] = [];
      def.parts.forEach((p) => {
        const mesh = new THREE.Mesh(buildPartGeometry(p.kind, p.size), mats[p.mat]);
        mesh.position.set(p.pos[0], p.pos[1], p.pos[2]);
        mesh.rotation.order = "YXZ";
        mesh.rotation.set(p.rot[0] * DEG, p.rot[1] * DEG, p.rot[2] * DEG);
        if (p.scale) mesh.scale.set(p.scale[0], p.scale[1], p.scale[2]);
        root.add(mesh);
        if (p.glow) glows.push(mesh);
      });
      if (def.modelScale) root.scale.set(def.modelScale[0], def.modelScale[1], def.modelScale[2]);
      turntable.add(root);
      models.push(root);
      glowSets.push(glows);
    });

    // ---- music flares ----
    const flareTex = [0, 1, 2, 3].map((s) => flareTexture(s));
    const flares: THREE.Sprite[] = [];
    FLARE_LAYOUT.forEach((f) => {
      const mat = new THREE.SpriteMaterial({
        map: flareTex[f.style % 4],
        color: "#2ef2ff",
        blending: THREE.AdditiveBlending,
        depthWrite: false,
        transparent: true,
        opacity: 0,
      });
      const sp = new THREE.Sprite(mat);
      sp.position.set(f.pos[0], f.pos[1], f.pos[2]);
      turntable.add(sp);
      flares.push(sp);
    });

    // ---- engine glow sprites (repositioned per ship) ----
    const ENGINE_POS: [number, number, number][][] = [
      [[-0.62, -0.02, 1.72], [0.62, -0.02, 1.72]],
      [[-0.78, -0.05, 2.19], [0.78, -0.05, 2.19]],
    ];
    const engineSprites: THREE.Sprite[] = [];
    for (let i = 0; i < 2; i++) {
      const mat = new THREE.SpriteMaterial({
        map: flareTex[0],
        color: "#2ef2ff",
        blending: THREE.AdditiveBlending,
        depthWrite: false,
        transparent: true,
        opacity: 0.85,
      });
      const sp = new THREE.Sprite(mat);
      sp.scale.set(1.1, 1.1, 1);
      turntable.add(sp);
      engineSprites.push(sp);
    }

    const shipLight = new THREE.PointLight(0x2ef2ff, 8, 10, 1.8);
    shipLight.position.set(0, 1.0, -2.2);
    turntable.add(shipLight);

    // ---- interaction ----
    let dragging = false;
    let px = 0;
    let py = 0;
    const el = renderer.domElement;
    el.style.cursor = "grab";
    const onDown = (e: PointerEvent) => {
      dragging = true;
      px = e.clientX;
      py = e.clientY;
      el.setPointerCapture(e.pointerId);
      el.style.cursor = "grabbing";
    };
    const onMove = (e: PointerEvent) => {
      if (!dragging) return;
      theta -= (e.clientX - px) * 0.008;
      phi = THREE.MathUtils.clamp(phi - (e.clientY - py) * 0.006, 0.2, 1.45);
      px = e.clientX;
      py = e.clientY;
      applyCamera();
    };
    const onUp = () => {
      dragging = false;
      el.style.cursor = "grab";
    };
    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      radius = THREE.MathUtils.clamp(radius * (1 + e.deltaY * 0.001), baseRadius * 0.45, baseRadius * 1.9);
      applyCamera();
    };
    el.addEventListener("pointerdown", onDown);
    el.addEventListener("pointermove", onMove);
    el.addEventListener("pointerup", onUp);
    el.addEventListener("wheel", onWheel, { passive: false });

    const resize = () => {
      const w = mount.clientWidth;
      const h = mount.clientHeight;
      if (w === 0 || h === 0) return;
      renderer.setSize(w, h, false);
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
    };
    const ro = new ResizeObserver(resize);
    ro.observe(mount);
    resize();

    // ---- animation ----
    const clock = new THREE.Clock();
    let raf = 0;
    let t = 0;
    let pulse = 0;
    let shownShip = -1;
    let frame = 0;
    const tmpColor = new THREE.Color();
    const engineColor = new THREE.Color("#2ef2ff");

    const animate = () => {
      raf = requestAnimationFrame(animate);
      const dt = Math.min(clock.getDelta(), 0.05);
      t += dt;
      frame++;
      const s = settings.current;
      const shipId = THREE.MathUtils.clamp(s.shipId, 0, SHIPS.length - 1);

      if (shipId !== shownShip) {
        shownShip = shipId;
        pulse = 1;
        models.forEach((m, i) => {
          m.visible = i === shipId;
        });
        engineColor.set(SHIPS[shipId].engine);
        rim.color.copy(engineColor).lerp(new THREE.Color("#ffffff"), 0.15);
        shipLight.color.copy(engineColor);
        engineSprites.forEach((sp, i) => {
          const p = ENGINE_POS[shipId][i];
          sp.position.set(p[0], p[1], p[2]);
          (sp.material as THREE.SpriteMaterial).color.copy(engineColor);
        });
      }
      pulse = Math.max(0, pulse - dt * 2.2);

      if (s.autoRotate) turntable.rotation.y += dt * (0.55 + pulse * 4.0);
      turntable.position.y = 1.2 + Math.sin(t * 1.6) * 0.07;
      const vis = models[shipId];
      vis.rotation.z = Math.sin(t * 1.1) * 0.04;
      vis.rotation.x = Math.sin(t * 0.9 + 1.3) * 0.03;
      ringA.rotation.z += dt * 0.25;
      ringB.rotation.z -= dt * 0.18;

      // Layers: idle wave always, simulated 124 BPM track on top when enabled.
      const idle = {
        bass: 0.3 + 0.22 * Math.sin(t * 2.2),
        drone: 0.3 + 0.2 * Math.sin(t * 0.9 + 2.0),
        melody: 0.25 + 0.2 * Math.sin(t * 1.4 + 4.0),
        perc: Math.max(0, Math.sin(t * 4.4)) * 0.22,
      };
      let bass = idle.bass;
      let drone = idle.drone;
      let melody = idle.melody;
      let perc = idle.perc;
      if (s.musicSim) {
        const beatPhase = (t * 124 / 60) % 1;
        const beat = Math.exp(-beatPhase * 6);
        const verse = 0.65 + 0.35 * Math.sin(t * 0.35);
        const dropT = t % 15.5;
        const drop = dropT < 2.5 ? Math.sin((dropT / 2.5) * Math.PI) : 0;
        bass = Math.max(idle.bass, beat * (0.45 + 0.4 * verse) + drop * 0.6);
        drone = Math.max(idle.drone, 0.35 + 0.2 * Math.sin(t * 0.8) + drop * 0.15);
        melody = Math.max(idle.melody, 0.3 + 0.45 * Math.max(0, Math.sin(t * 1.7)) * verse + drop * 0.3);
        perc = Math.max(idle.perc, beat * 0.8 * (0.4 + 0.6 * verse) + drop * 0.5);
      }
      const scores: [string, number][] = [
        ["BASS", bass],
        ["DRONE", drone * 0.9],
        ["MELODY", melody],
        ["PERCUSSION", perc],
      ];
      scores.sort((a, b) => b[1] - a[1]);
      const dominant = scores[0][1] < 0.05 ? "SILENT" : scores[0][0];

      const gs = 1 + bass * 0.35 + perc * 0.2 + pulse * 0.6 + Math.sin(t * 9) * 0.03;
      glowSets[shipId].forEach((g) => g.scale.set(gs, gs, gs));
      shipLight.intensity = 8 * (1 + bass * 0.8 + melody * 0.4 + perc * 0.5 + pulse * 1.2);
      engineSprites.forEach((sp) => {
        const es = 0.9 + bass * 0.5 + pulse * 0.9;
        sp.scale.set(es, es, 1);
        (sp.material as THREE.SpriteMaterial).opacity = 0.55 + Math.min(0.45, bass * 0.4 + pulse * 0.4);
      });

      tmpColor.copy(PALETTE[dominant] ?? engineColor).lerp(engineColor, 0.25);
      const values = [bass + pulse * 0.8, melody, melody, perc, perc, drone * 0.7 + melody * 0.25];
      flares.forEach((sp, i) => {
        const m = sp.material as THREE.SpriteMaterial;
        const value = THREE.MathUtils.clamp(values[i], 0, 1.4);
        m.color.copy(tmpColor);
        m.opacity = s.showFlares ? THREE.MathUtils.clamp(value * 0.85, 0, 1) : 0;
        const f = FLARE_LAYOUT[i];
        const sc = f.size * (0.75 + value * (i === 0 ? 1.2 : 0.65));
        sp.scale.set(sc, sc, 1);
        sp.visible = m.opacity > 0.02;
      });

      if (frame % 6 === 0) {
        if (layerRef.current) layerRef.current.textContent = dominant;
        if (barsRef.current) {
          const kids = barsRef.current.children;
          const vals = [bass, drone, melody, perc];
          for (let i = 0; i < 4 && i < kids.length; i++) {
            const bar = kids[i].children[1] as HTMLElement | undefined;
            const fillEl = bar?.children[0] as HTMLElement | undefined;
            if (fillEl) fillEl.style.width = `${Math.round(THREE.MathUtils.clamp(vals[i], 0, 1) * 100)}%`;
          }
        }
      }

      renderer.render(scene, camera);
    };

    animate();

    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
      el.removeEventListener("pointerdown", onDown);
      el.removeEventListener("pointermove", onMove);
      el.removeEventListener("pointerup", onUp);
      el.removeEventListener("wheel", onWheel);
      scene.traverse((o) => {
        const mesh = o as THREE.Mesh;
        if (mesh.geometry) mesh.geometry.dispose();
        const mat = (mesh as THREE.Mesh).material as THREE.Material | THREE.Material[] | undefined;
        if (Array.isArray(mat)) mat.forEach((m) => m.dispose());
        else if (mat) mat.dispose();
      });
      flareTex.forEach((x) => x.dispose());
      renderer.dispose();
      mount.removeChild(renderer.domElement);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div className="viewer-wrap" style={props.height ? { height: props.height } : undefined}>
      <div ref={mountRef} className="viewer-canvas" />
      <div className="viewer-hud">
        <span className="viewer-layer">
          LAYER <span ref={layerRef}>DRONE</span>
        </span>
        <div ref={barsRef} className="viewer-bars">
          <div className="vbar"><i>B</i><b><u /></b></div>
          <div className="vbar"><i>D</i><b><u /></b></div>
          <div className="vbar"><i>M</i><b><u /></b></div>
          <div className="vbar"><i>P</i><b><u /></b></div>
        </div>
      </div>
      <div className="viewer-hint">DRAG TO ORBIT • SCROLL TO ZOOM</div>
    </div>
  );
}
