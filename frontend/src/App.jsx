import React, { useEffect, useState } from 'react'
import { Routes, Route, useNavigate } from 'react-router-dom'
import { login, listRooms, roomGlbUrl, deleteRoom } from './api'
import HeroBg from './HeroBg'
import RoomThumbnail from './RoomThumbnail'
import Navbar from './Navbar'
import UploadPage from './UploadPage'
import RoomViewerPage from './RoomViewerPage'
import DemoViewerPage from './DemoViewerPage'

const DEMO_ROOMS = [
  {
    id: 'sketchfab-927ef282eceb47e29397b52147d4d6c3',
    name: 'Living Room',
    category: 'Home',
    sketchfabId: '927ef282eceb47e29397b52147d4d6c3',
    author: 'fleewortep',
  },
  {
    id: 'sketchfab-44e7a9cfed67431e827d0cbaabd462c7',
    name: 'Loft Apartment',
    category: 'Home',
    sketchfabId: '44e7a9cfed67431e827d0cbaabd462c7',
    author: 'Zeps3D',
  },
  {
    id: 'sketchfab-3ecfa670dbd946ec80b49d7df74ab453',
    name: 'Modular Classroom Preview',
    category: 'Education',
    sketchfabId: '3ecfa670dbd946ec80b49d7df74ab453',
    author: 'lazarys',
  },
  {
    id: 'sketchfab-79615d823a9149069dcd06c20bc9707f',
    name: 'The Billiards Room',
    category: 'Other',
    sketchfabId: '79615d823a9149069dcd06c20bc9707f',
    author: 'The Hallwyl Museum',
  },
]

const CATEGORY_ORDER = ['Home', 'Education', 'Office', 'Other']

function groupByCategory(rooms) {
  const map = {}
  for (const room of rooms) {
    const cat = room.category || 'Other'
    if (!map[cat]) map[cat] = []
    map[cat].push(room)
  }
  return CATEGORY_ORDER.filter((c) => map[c]).map((c) => ({ category: c, rooms: map[c] }))
}

function getSavedUser() {
  try { return JSON.parse(sessionStorage.getItem('mentis_user')) } catch { return null }
}
function saveUser(u)  { sessionStorage.setItem('mentis_user', JSON.stringify(u)) }
function clearUser()  { sessionStorage.removeItem('mentis_user') }

export default function App() {
  const navigate = useNavigate()
  const [user, setUser]             = useState(getSavedUser)
  const [emailInput, setEmail]      = useState('')
  const [loginError, setLoginError] = useState(null)
  const [loggingIn, setLoggingIn]   = useState(false)
  const [rooms, setRooms]           = useState([])

  useEffect(() => {
    if (user) listRooms(user.user_id).then((r) => setRooms(r.rooms ?? []))
  }, [user])

  async function doLogin(email) {
    setLoggingIn(true); setLoginError(null)
    try {
      const u = await login(email)
      saveUser(u); setUser(u)
    } catch (err) {
      setLoginError(err.message || String(err))
    } finally {
      setLoggingIn(false)
    }
  }

  function handleLogout() {
    clearUser(); setUser(null); setRooms([]); navigate('/')
  }

  async function onDeleteRoom(room) {
    if (!window.confirm(`Delete "${room.name}"? This cannot be undone.`)) return
    try {
      await deleteRoom(room.id)
      const roomsData = await listRooms(user.user_id)
      setRooms(roomsData.rooms ?? [])
    } catch (err) {
      alert(`Delete failed: ${err.message}`)
    }
  }

  return (
    <div className="app">
      <Navbar user={user} onLogout={handleLogout} />

      <Routes>
        <Route path="/upload" element={<UploadPage user={user} onUploaded={setRooms} />} />
        <Route path="/rooms/:id"       element={<RoomViewerPage />} />
        <Route path="/demo/:modelId"   element={<DemoViewerPage />} />

        <Route path="*" element={
          <>
            {/* ── Hero ── */}
            <header className="hero-header">
              <HeroBg />
              <div className="hero-content">
                <h1>Mentis</h1>
                <p className="hero-subtitle">Your 3D Memory Palace</p>

                {!user && (
                  <form className="login-form" onSubmit={(e) => { e.preventDefault(); if (emailInput.trim()) doLogin(emailInput.trim()) }}>
                    <input
                      className="login-input"
                      type="email"
                      placeholder="your@email.com"
                      value={emailInput}
                      onChange={(e) => setEmail(e.target.value)}
                      required
                    />
                    <button className="login-btn" type="submit" disabled={loggingIn}>
                      {loggingIn ? 'Signing in…' : 'Sign in'}
                    </button>
                    <button className="login-btn demo" type="button" disabled={loggingIn} onClick={() => doLogin('demo@mentis.app')}>
                      Try demo
                    </button>
                    {loginError && <p className="login-error">{loginError}</p>}
                  </form>
                )}
              </div>
            </header>

            {/* ── My Rooms ── */}
            {user && rooms.length > 0 && (
              <section className="rooms">
                <h2>My Rooms</h2>
                <div className="rooms-grid">
                  {rooms.map((r) => (
                    <div
                      key={r.id}
                      className="room-card"
                      onClick={() => navigate(`/rooms/${r.id}`, { state: { roomName: r.name } })}
                    >
                      <RoomThumbnail glbUrl={roomGlbUrl(r.id)} />
                      <div className="room-card-footer">
                        <strong className="room-card-name">{r.name}</strong>
                        <button
                          className="room-delete-btn"
                          onClick={(e) => { e.stopPropagation(); onDeleteRoom(r) }}
                          title="Delete room"
                        >×</button>
                      </div>
                    </div>
                  ))}
                </div>
              </section>
            )}

            {/* ── Demo Rooms ── */}
            <section className="demo-rooms">
              <h2>Demo Rooms</h2>
              {groupByCategory(DEMO_ROOMS).map(({ category, rooms: catRooms }) => (
                <div key={category} className="demo-rooms-category">
                  <h3 className="demo-rooms-category-label">{category}</h3>
                  <div className="demo-rooms-grid">
                    {catRooms.map((room) => (
                      <div
                        key={room.id}
                        className="demo-room-card"
                        onClick={() => navigate(`/demo/${room.sketchfabId}`, { state: { roomName: room.name } })}
                      >
                        <div className="demo-room-thumb">
                          <iframe
                            title={room.name}
                            src={`https://sketchfab.com/models/${room.sketchfabId}/embed?autostart=0&ui_controls=0&ui_infos=0&ui_inspector=0&ui_watermark=0`}
                            frameBorder="0"
                            allowFullScreen
                            allow="autoplay; fullscreen; xr-spatial-tracking"
                            tabIndex="-1"
                          />
                          <div className="demo-room-overlay"><span>Open in Viewer</span></div>
                        </div>
                        <div className="demo-room-info">
                          <strong>{room.name}</strong>
                          <span className="demo-room-author">by {room.author}</span>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </section>
          </>
        } />
      </Routes>
    </div>
  )
}
