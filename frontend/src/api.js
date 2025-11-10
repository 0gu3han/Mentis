// src/api.js
const BASE = import.meta.env.VITE_API_BASE || 'http://localhost:5001'

export async function login(email) {
  try {
    const res = await fetch(`${BASE}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email })
    })
    if (!res.ok) {
      const error = await res.json().catch(() => ({ error: `HTTP ${res.status}: ${res.statusText}` }))
      throw new Error(error.error || `Login failed with status ${res.status}`)
    }
    return res.json()
  } catch (err) {
    console.error('login() network/error:', err)
    throw err
  }
}

export async function createRoom(user_id, name, file) {
  const fd = new FormData()
  fd.append('user_id', String(user_id))
  fd.append('name', name)
  fd.append('file', file)
  const res = await fetch(`${BASE}/rooms`, { method: 'POST', body: fd })
  if (!res.ok) {
    const error = await res.json().catch(() => ({ error: `HTTP ${res.status}: ${res.statusText}` }))
    throw new Error(error.error || `Upload failed with status ${res.status}`)
  }
  return res.json()
}

export async function listRooms(user_id) {
  const url = new URL(`${BASE}/rooms`)
  if (user_id) url.searchParams.set('user_id', user_id)
  const res = await fetch(url)
  return res.json()
}

export function roomGlbUrl(room_id) {
  return `${BASE}/rooms/${room_id}/glb`
}

export async function listAnchors(room_id) {
  const url = new URL(`${BASE}/anchors`)
  url.searchParams.set('room_id', room_id)
  const res = await fetch(url)
  if (!res.ok) {
    const error = await res.json().catch(() => ({ error: `HTTP ${res.status}: ${res.statusText}` }))
    throw new Error(error.error || `listAnchors failed with status ${res.status}`)
  }
  return res.json()
}

export async function createAnchor(data) {
  const res = await fetch(`${BASE}/anchors`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data)
  })
  if (!res.ok) {
    const error = await res.json().catch(() => ({ error: `HTTP ${res.status}: ${res.statusText}` }))
    throw new Error(error.error || `createAnchor failed with status ${res.status}`)
  }
  return res.json()
}

export async function createObject(data) {
  const res = await fetch(`${BASE}/objects`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data)
  })
  if (!res.ok) {
    const error = await res.json().catch(() => ({ error: `HTTP ${res.status}: ${res.statusText}` }))
    throw new Error(error.error || `createObject failed with status ${res.status}`)
  }
  return res.json()
}

export async function getNextReview(room_id) {
  const url = new URL(`${BASE}/review/next`)
  if (room_id) url.searchParams.set('room_id', room_id)
  const res = await fetch(url)
  return res.json()
}
