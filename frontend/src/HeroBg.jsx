// src/HeroBg.jsx — Animated Three.js background (Laravel-style floating shapes)
import { useEffect, useRef } from 'react'
import * as THREE from 'three'

const SHAPE_COUNT = 30

// Each shape: geometry factory, scale range, base color
const SHAPE_DEFS = [
  { make: () => new THREE.BoxGeometry(1, 1, 1),          minS: 0.30, maxS: 0.95 },
  { make: () => new THREE.OctahedronGeometry(0.6),       minS: 0.35, maxS: 1.05 },
  { make: () => new THREE.TetrahedronGeometry(0.7),      minS: 0.30, maxS: 0.90 },
  { make: () => new THREE.IcosahedronGeometry(0.5, 0),   minS: 0.35, maxS: 1.00 },
]

function rand(min, max) { return min + Math.random() * (max - min) }

export default function HeroBg() {
  const canvasRef = useRef()

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return

    // ── Renderer ────────────────────────────────────────────────────────────
    const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true })
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
    renderer.setClearColor(0x000000, 0)

    // ── Scene / Camera ───────────────────────────────────────────────────────
    const scene  = new THREE.Scene()
    scene.fog = new THREE.FogExp2(0x0a0e14, 0.06)
    const camera = new THREE.PerspectiveCamera(55, 1, 0.1, 100)
    camera.position.z = 5

    // ── Lights ───────────────────────────────────────────────────────────────
    scene.add(new THREE.AmbientLight(0xffffff, 0.6))
    const pt = new THREE.PointLight(0xa8b4ff, 10, 22)
    pt.position.set(3, 4, 4)
    scene.add(pt)
    const pt2 = new THREE.PointLight(0x5de8d8, 6, 16)
    pt2.position.set(-4, -2, 3)
    scene.add(pt2)

    // ── Shapes ───────────────────────────────────────────────────────────────
    const shapes = []
    for (let i = 0; i < SHAPE_COUNT; i++) {
      const def = SHAPE_DEFS[i % SHAPE_DEFS.length]
      const geo = def.make()

      // Alternate between wireframe-edged and semi-transparent solid
      const isWire = Math.random() < 0.45
      const mat = isWire
        ? new THREE.MeshStandardMaterial({
            color: 0xa8b4ff,
            wireframe: true,
            opacity: rand(0.55, 0.85),
            transparent: true,
          })
        : new THREE.MeshStandardMaterial({
            color: i % 3 === 0 ? 0xa8b4ff : i % 3 === 1 ? 0x7b9fff : 0x5de8d8,
            roughness: 0.3,
            metalness: 0.7,
            opacity: rand(0.35, 0.65),
            transparent: true,
          })

      const mesh = new THREE.Mesh(geo, mat)
      const s = rand(def.minS, def.maxS)
      mesh.scale.setScalar(s)

      // Spread across a wide view frustum plane
      mesh.position.set(rand(-9, 9), rand(-5, 5), rand(-5, 1))

      // Random initial rotation
      mesh.rotation.set(rand(0, Math.PI * 2), rand(0, Math.PI * 2), rand(0, Math.PI * 2))

      // Per-shape animation params
      mesh.userData = {
        vy:       rand(-0.004, 0.004),   // drift speed Y
        vx:       rand(-0.002, 0.002),   // drift speed X
        rx:       rand(0.002, 0.008) * (Math.random() < 0.5 ? 1 : -1),
        ry:       rand(0.003, 0.010) * (Math.random() < 0.5 ? 1 : -1),
        rz:       rand(0.001, 0.005) * (Math.random() < 0.5 ? 1 : -1),
        bobAmp:   rand(0.08, 0.22),      // bob amplitude
        bobFreq:  rand(0.4, 1.1),        // bob frequency (rad/s)
        bobPhase: rand(0, Math.PI * 2),  // phase offset so they don't all move in sync
        originY:  mesh.position.y,
      }

      scene.add(mesh)
      shapes.push(mesh)
    }

    // ── Resize helper ────────────────────────────────────────────────────────
    function resize() {
      const w = canvas.parentElement?.clientWidth  || window.innerWidth
      const h = canvas.parentElement?.clientHeight || 220
      renderer.setSize(w, h, false)
      camera.aspect = w / h
      camera.updateProjectionMatrix()
    }
    resize()
    window.addEventListener('resize', resize)

    // ── Render loop ──────────────────────────────────────────────────────────
    let raf
    const clock = new THREE.Clock()

    function tick() {
      raf = requestAnimationFrame(tick)
      const t = clock.getElapsedTime()

      shapes.forEach((mesh) => {
        const d = mesh.userData
        // Bobbing (sine wave)
        mesh.position.y = d.originY + Math.sin(t * d.bobFreq + d.bobPhase) * d.bobAmp
        // Slow drift
        mesh.position.x += d.vx
        mesh.position.y += d.vy
        // Wrap around edges so shapes never disappear
        if (mesh.position.x > 10) mesh.position.x = -10
        if (mesh.position.x < -10) mesh.position.x =  10
        if (mesh.position.y >  6) { mesh.position.y = -6; mesh.userData.originY = -6 }
        if (mesh.position.y < -6) { mesh.position.y =  6; mesh.userData.originY =  6 }
        // Rotation
        mesh.rotation.x += d.rx
        mesh.rotation.y += d.ry
        mesh.rotation.z += d.rz
      })

      // Slowly orbit the indigo point light for extra drama
      pt.position.x = Math.sin(t * 0.3) * 5
      pt.position.y = Math.cos(t * 0.2) * 3

      renderer.render(scene, camera)
    }
    tick()

    return () => {
      cancelAnimationFrame(raf)
      window.removeEventListener('resize', resize)
      shapes.forEach((m) => { m.geometry.dispose(); m.material.dispose() })
      renderer.dispose()
    }
  }, [])

  return (
    <canvas
      ref={canvasRef}
      className="hero-bg-canvas"
      aria-hidden="true"
    />
  )
}
