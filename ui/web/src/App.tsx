import { Routes, Route, Navigate } from 'react-router-dom';
import { Layout } from './components/Layout';
import Dashboard from './routes/Dashboard';
import AgentsControlPanel from './routes/AgentsControlPanel';
import Settings from './routes/Settings';
import Logs from './routes/Logs';

// Four tabs only: Dashboard / Agents / Settings / Logs. The former standalone
// views (brief, pending, pitch-deck, newsletter, resurfacer, signals, feedback,
// diagnostics) were folded into these four.
export default function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Dashboard />} />
        <Route path="agents" element={<AgentsControlPanel />} />
        <Route path="settings" element={<Settings />} />
        <Route path="logs" element={<Logs />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  );
}
