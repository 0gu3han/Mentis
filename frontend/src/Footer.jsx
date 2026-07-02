import { Link } from 'react-router-dom'

export default function Footer() {
  return (
    <footer className="app-footer">
      <div className="footer-inner">
        <span className="footer-brand">Mentis</span>
        <span className="footer-sep">·</span>
        <span className="footer-tagline">Your 3D Memory Palace</span>
        <div className="footer-links">
          <Link to="/">Home</Link>
          <Link to="/upload">Upload Room</Link>
        </div>
      </div>
    </footer>
  )
}
