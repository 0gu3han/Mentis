// Decorative static geometric background for the room library sections.
// Pure SVG — no WebGL context used.

function IsoCube({ x, y, s, color, opacity }) {
  // Isometric cube: top rhombus + left face + right face
  // w = half-width of each face, h = half-height of rhombus, d = depth of sides
  const w = s, h = s * 0.5, d = s * 0.5
  const top   = `${x},${y} ${x+w},${y+h} ${x},${y+h*2} ${x-w},${y+h}`
  const left  = `${x-w},${y+h} ${x-w},${y+h+d} ${x},${y+h*2+d} ${x},${y+h*2}`
  const right = `${x},${y+h*2} ${x+w},${y+h} ${x+w},${y+h+d} ${x},${y+h*2+d}`
  return (
    <g stroke={color} fill="none" strokeWidth="0.9" opacity={opacity}>
      <polygon points={top}   />
      <polygon points={left}  />
      <polygon points={right} />
    </g>
  )
}

function Hexagon({ x, y, r, color, opacity }) {
  const pts = Array.from({ length: 6 }, (_, i) => {
    const a = (i * 60 - 30) * (Math.PI / 180)
    return `${x + r * Math.cos(a)},${y + r * Math.sin(a)}`
  }).join(' ')
  return <polygon points={pts} fill="none" stroke={color} strokeWidth="0.8" opacity={opacity} />
}

function Diamond({ x, y, s, color, opacity }) {
  return (
    <polygon
      points={`${x},${y-s} ${x+s},${y} ${x},${y+s} ${x-s},${y}`}
      fill="none" stroke={color} strokeWidth="0.8" opacity={opacity}
    />
  )
}

function OctoRing({ x, y, r, color, opacity }) {
  // Octagon
  const pts = Array.from({ length: 8 }, (_, i) => {
    const a = (i * 45) * (Math.PI / 180)
    return `${x + r * Math.cos(a)},${y + r * Math.sin(a)}`
  }).join(' ')
  return <polygon points={pts} fill="none" stroke={color} strokeWidth="0.8" opacity={opacity} />
}

const INDIGO = '#666fca'
const TEAL   = '#66d9cc'

export default function LibraryBg() {
  return (
    <svg
      className="library-bg"
      viewBox="0 0 1440 1100"
      xmlns="http://www.w3.org/2000/svg"
      preserveAspectRatio="xMidYMin slice"
      aria-hidden="true"
    >
      {/* ── Large cubes at corners ── */}
      <IsoCube x={1280} y={20}  s={90}  color={INDIGO} opacity={0.07} />
      <IsoCube x={80}   y={60}  s={70}  color={TEAL}   opacity={0.06} />
      <IsoCube x={1350} y={480} s={55}  color={TEAL}   opacity={0.06} />
      <IsoCube x={40}   y={420} s={75}  color={INDIGO} opacity={0.05} />
      <IsoCube x={1130} y={850} s={100} color={INDIGO} opacity={0.05} />
      <IsoCube x={240}  y={820} s={60}  color={TEAL}   opacity={0.06} />

      {/* ── Mid-field cubes ── */}
      <IsoCube x={670}  y={40}  s={40}  color={TEAL}   opacity={0.04} />
      <IsoCube x={900}  y={950} s={50}  color={INDIGO} opacity={0.05} />
      <IsoCube x={430}  y={550} s={32}  color={INDIGO} opacity={0.04} />
      <IsoCube x={1020} y={280} s={45}  color={TEAL}   opacity={0.05} />

      {/* ── Hexagons ── */}
      <Hexagon  x={560}  y={130} r={42} color={INDIGO} opacity={0.06} />
      <Hexagon  x={1190} y={560} r={34} color={TEAL}   opacity={0.07} />
      <Hexagon  x={190}  y={640} r={28} color={INDIGO} opacity={0.05} />
      <Hexagon  x={760}  y={870} r={50} color={TEAL}   opacity={0.05} />
      <Hexagon  x={380}  y={200} r={22} color={TEAL}   opacity={0.05} />

      {/* ── Diamonds ── */}
      <Diamond  x={1370} y={220} s={30} color={TEAL}   opacity={0.07} />
      <Diamond  x={100}  y={250} s={22} color={INDIGO} opacity={0.06} />
      <Diamond  x={720}  y={600} s={26} color={INDIGO} opacity={0.04} />
      <Diamond  x={1240} y={730} s={18} color={TEAL}   opacity={0.06} />
      <Diamond  x={490}  y={940} s={24} color={INDIGO} opacity={0.05} />

      {/* ── Octagons ── */}
      <OctoRing x={840}  y={120} r={36} color={INDIGO} opacity={0.05} />
      <OctoRing x={310}  y={380} r={24} color={TEAL}   opacity={0.05} />
      <OctoRing x={1080} y={680} r={30} color={TEAL}   opacity={0.05} />
      <OctoRing x={620}  y={760} r={20} color={INDIGO} opacity={0.04} />
    </svg>
  )
}
