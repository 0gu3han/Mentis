// src/api.js
const BASE = import.meta.env.VITE_API_BASE || ''

export async function login(email) {
  const res = await fetch(`${BASE}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email })
  })
  const data = await res.json().catch(() => ({ error: `HTTP ${res.status}: ${res.statusText}` }))
  if (!res.ok) throw new Error(data.error || `Login failed with status ${res.status}`)
  return data
}

export async function register(email) {
  const res = await fetch(`${BASE}/auth/register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email })
  })
  const data = await res.json().catch(() => ({ error: `HTTP ${res.status}: ${res.statusText}` }))
  if (!res.ok) throw new Error(data.error || `Register failed with status ${res.status}`)
  return data
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
  const qs = user_id ? `?user_id=${encodeURIComponent(user_id)}` : ''
  const res = await fetch(`${BASE}/rooms${qs}`)
  return res.json()
}

export function roomGlbUrl(room_id) {
  return `${BASE}/rooms/${room_id}/glb`
}

export async function listAnchors(room_id) {
  const res = await fetch(`${BASE}/anchors?room_id=${encodeURIComponent(room_id)}`)
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

export async function deleteRoom(room_id) {
  const res = await fetch(`${BASE}/rooms/${room_id}`, { method: 'DELETE' })
  if (!res.ok) {
    const error = await res.json().catch(() => ({ error: `HTTP ${res.status}: ${res.statusText}` }))
    throw new Error(error.error || `deleteRoom failed with status ${res.status}`)
  }
  return res.json()
}

export async function deleteAnchor(anchor_id) {
  const res = await fetch(`${BASE}/anchors/${anchor_id}`, { method: 'DELETE' })
  if (!res.ok) {
    const error = await res.json().catch(() => ({ error: `HTTP ${res.status}: ${res.statusText}` }))
    throw new Error(error.error || `deleteAnchor failed with status ${res.status}`)
  }
  return res.json()
}

export async function getNextReview(room_id) {
  const qs = room_id ? `?room_id=${encodeURIComponent(room_id)}` : ''
  const res = await fetch(`${BASE}/review/next${qs}`)
  return res.json()
}
