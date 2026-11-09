// Marker icons, drawn with canvas paths. One icon for each journal kind; the map and the timeline share them.
// Ported from the first viewer ("Memories Chronicle").

export function icon(ctx, kind, x, y, r, alpha) {
  ctx.save(); ctx.globalAlpha = alpha == null ? 1 : alpha; ctx.lineWidth = 1.6; ctx.strokeStyle = '#0c0803'; ctx.lineJoin = 'round';
  const circle = (fill) => { ctx.beginPath(); ctx.arc(x, y, r, 0, 6.2832); ctx.fillStyle = fill; ctx.fill(); ctx.stroke(); };
  switch (kind) {
    case 'lv': {
      ctx.beginPath();
      for (let n = 0; n < 10; n++) { const rr = n % 2 ? r * 0.45 : r * 1.15, a = -Math.PI / 2 + n * Math.PI / 5; ctx[n ? 'lineTo' : 'moveTo'](x + Math.cos(a) * rr, y + Math.sin(a) * rr); }
      ctx.closePath(); ctx.fillStyle = '#ffd100'; ctx.fill(); ctx.stroke(); break;
    }
    case 'de': {
      circle('#eee6d2'); ctx.fillStyle = '#2a0504';
      ctx.beginPath(); ctx.arc(x - r * 0.38, y - r * 0.12, r * 0.24, 0, 6.2832); ctx.arc(x + r * 0.38, y - r * 0.12, r * 0.24, 0, 6.2832); ctx.fill();
      ctx.fillRect(x - r * 0.1, y + r * 0.2, r * 0.2, r * 0.35);
      ctx.strokeStyle = '#a3170c'; ctx.lineWidth = 1.2; ctx.beginPath(); ctx.arc(x, y, r, 0, 6.2832); ctx.stroke(); break;
    }
    case 'cc': case 'pk': {
      if (kind === 'cc') {
        ctx.beginPath(); ctx.moveTo(x, y - r * 1.1); ctx.lineTo(x + r * 1.05, y + r * 0.85); ctx.lineTo(x - r * 1.05, y + r * 0.85); ctx.closePath();
        ctx.fillStyle = '#ff8a1c'; ctx.fill(); ctx.stroke(); ctx.fillStyle = '#2a1200'; ctx.fillRect(x - 1, y - r * 0.4, 2, r * 0.6); ctx.fillRect(x - 1, y + r * 0.4, 2, 2);
      } else {
        circle('#c0392b'); ctx.strokeStyle = '#fff'; ctx.lineWidth = 1.6; ctx.beginPath();
        ctx.moveTo(x - r * 0.5, y - r * 0.5); ctx.lineTo(x + r * 0.5, y + r * 0.5); ctx.moveTo(x + r * 0.5, y - r * 0.5); ctx.lineTo(x - r * 0.5, y + r * 0.5); ctx.stroke();
      }
      break;
    }
    case 'dn': case 'bo': {
      ctx.beginPath(); ctx.moveTo(x, y - r * 1.2); ctx.lineTo(x + r * 1.1, y); ctx.lineTo(x, y + r * 1.2); ctx.lineTo(x - r * 1.1, y); ctx.closePath();
      ctx.fillStyle = kind === 'dn' ? '#a45ee8' : '#c4143f'; ctx.fill(); ctx.stroke();
      if (kind === 'bo') { ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(x, y, r * 0.3, 0, 6.2832); ctx.fill(); }
      break;
    }
    case 'qt': case 'di': {
      circle(kind === 'qt' ? '#ffd100' : '#5ec9ff'); ctx.fillStyle = '#2a1c00';
      if (kind === 'qt') { ctx.fillRect(x - 1, y - r * 0.6, 2, r * 0.85); ctx.fillRect(x - 1, y + r * 0.45, 2, 2); } else { ctx.beginPath(); ctx.arc(x, y, r * 0.3, 0, 6.2832); ctx.fill(); }
      break;
    }
    case 'hs': case 'tx': {
      circle('#2f7fff'); ctx.fillStyle = '#fff';
      if (kind === 'hs') { ctx.fillRect(x - r * 0.45, y - r * 0.5, 1.8, r); ctx.fillRect(x + r * 0.45 - 1.8, y - r * 0.5, 1.8, r); ctx.fillRect(x - r * 0.45, y - 0.9, r * 0.9, 1.8); }
      else { ctx.beginPath(); ctx.moveTo(x + r * 0.6, y); ctx.lineTo(x - r * 0.45, y - r * 0.45); ctx.lineTo(x - r * 0.2, y); ctx.lineTo(x - r * 0.45, y + r * 0.45); ctx.closePath(); ctx.fill(); }
      break;
    }
    case 'ss': {
      ctx.fillStyle = '#d8e0ea'; ctx.beginPath(); ctx.rect(x - r, y - r * 0.6, r * 2, r * 1.4); ctx.fill(); ctx.stroke();
      ctx.fillRect(x - r * 0.4, y - r * 0.9, r * 0.8, r * 0.35);
      ctx.beginPath(); ctx.arc(x, y + r * 0.1, r * 0.45, 0, 6.2832); ctx.fillStyle = '#1b2638'; ctx.fill(); ctx.stroke(); break;
    }
    case 'ga': {
      ctx.beginPath(); for (let n = 0; n < 6; n++) { const a = Math.PI / 6 + n * Math.PI / 3; ctx[n ? 'lineTo' : 'moveTo'](x + Math.cos(a) * r * 1.1, y + Math.sin(a) * r * 1.1); }
      ctx.closePath(); ctx.fillStyle = '#35c9a0'; ctx.fill(); ctx.stroke(); ctx.fillStyle = '#eafff7'; ctx.beginPath(); ctx.arc(x - r * 0.25, y - r * 0.25, r * 0.28, 0, 6.2832); ctx.fill(); break;
    }
    case 'fs': {
      ctx.beginPath(); ctx.ellipse(x - r * 0.15, y, r * 0.95, r * 0.6, 0, 0, 6.2832); ctx.moveTo(x + r * 0.6, y); ctx.lineTo(x + r * 1.2, y - r * 0.55); ctx.lineTo(x + r * 1.2, y + r * 0.55); ctx.closePath();
      ctx.fillStyle = '#4fa8e0'; ctx.fill(); ctx.stroke(); ctx.fillStyle = '#06233a'; ctx.beginPath(); ctx.arc(x - r * 0.55, y - r * 0.12, r * 0.14, 0, 6.2832); ctx.fill(); break;
    }
    case 'op': {
      ctx.fillStyle = '#9a6a35'; ctx.beginPath(); ctx.rect(x - r, y - r * 0.55, r * 2, r * 1.25); ctx.fill(); ctx.stroke();
      ctx.fillStyle = '#c28a49'; ctx.fillRect(x - r, y - r * 0.55, r * 2, r * 0.45); ctx.fillStyle = '#ffd100'; ctx.fillRect(x - r * 0.18, y - r * 0.2, r * 0.36, r * 0.5); break;
    }
    case 'pp': {
      circle('#6d4a92'); ctx.fillStyle = '#ffd100'; ctx.beginPath(); ctx.arc(x, y + r * 0.1, r * 0.4, 0, 6.2832); ctx.fill();
      ctx.fillStyle = '#e9d9ff'; ctx.fillRect(x - r * 0.35, y - r * 0.7, r * 0.7, r * 0.22); break;
    }
    case 'rl': {
      ctx.fillStyle = '#f2ead6'; ctx.beginPath(); ctx.rect(x - r * 0.9, y - r * 0.9, r * 1.8, r * 1.8); ctx.fill(); ctx.stroke(); ctx.fillStyle = '#2a1c00';
      for (const [dx, dy] of [[-0.45, -0.45], [0.45, -0.45], [0, 0], [-0.45, 0.45], [0.45, 0.45]]) { ctx.beginPath(); ctx.arc(x + dx * r, y + dy * r, r * 0.16, 0, 6.2832); ctx.fill(); }
      break;
    }
    case 'rp': {
      ctx.beginPath(); ctx.moveTo(x - r * 0.8, y - r); ctx.lineTo(x + r * 0.8, y - r); ctx.lineTo(x + r * 0.8, y + r * 0.5); ctx.lineTo(x, y + r * 1.1); ctx.lineTo(x - r * 0.8, y + r * 0.5); ctx.closePath();
      ctx.fillStyle = '#3fbf6a'; ctx.fill(); ctx.stroke(); ctx.fillStyle = '#ffd100'; ctx.fillRect(x - r * 0.12, y - r * 0.6, r * 0.24, r * 0.9); break;
    }
    case 'qa': {
      circle('#2a1c00'); ctx.strokeStyle = '#ffd100'; ctx.lineWidth = 1.6; ctx.beginPath(); ctx.arc(x, y, r, 0, 6.2832); ctx.stroke();
      ctx.fillStyle = '#ffd100'; ctx.fillRect(x - 1, y - r * 0.6, 2, r * 0.85); ctx.fillRect(x - 1, y + r * 0.45, 2, 2); break;
    }
    case 'hb': {
      ctx.beginPath(); ctx.moveTo(x, y - r * 1.15); ctx.lineTo(x + r * 1.1, y - r * 0.1); ctx.lineTo(x + r * 0.8, y - r * 0.1); ctx.lineTo(x + r * 0.8, y + r * 0.9);
      ctx.lineTo(x - r * 0.8, y + r * 0.9); ctx.lineTo(x - r * 0.8, y - r * 0.1); ctx.lineTo(x - r * 1.1, y - r * 0.1); ctx.closePath();
      ctx.fillStyle = '#e08a3c'; ctx.fill(); ctx.stroke(); ctx.fillStyle = '#3a1e06'; ctx.fillRect(x - r * 0.2, y + r * 0.2, r * 0.4, r * 0.7); break;
    }
    case 'fp': {
      ctx.beginPath(); ctx.moveTo(x - r * 0.7, y - r * 1.1); ctx.lineTo(x + r * 0.9, y - r * 0.5); ctx.lineTo(x - r * 0.7, y + r * 0.1); ctx.closePath();
      ctx.fillStyle = '#6fa6ff'; ctx.fill(); ctx.stroke(); ctx.fillStyle = '#d8e6ff'; ctx.fillRect(x - r * 0.85, y - r * 1.1, r * 0.25, r * 2.2); break;
    }
    case 'bk': {
      ctx.fillStyle = '#a77b4a'; ctx.beginPath(); ctx.rect(x - r * 0.85, y - r, r * 1.7, r * 2); ctx.fill(); ctx.stroke();
      ctx.fillStyle = '#f2ead6'; ctx.fillRect(x - r * 0.55, y - r * 0.7, r * 1.3, r * 0.3); ctx.fillRect(x - r * 0.55, y - r * 0.15, r * 1.3, r * 0.3); break;
    }
    case 'pt': {
      circle('#5fae3a'); ctx.fillStyle = '#10240a';
      for (const [dx, dy] of [[-0.55, -0.15], [-0.2, -0.55], [0.2, -0.55], [0.55, -0.15]]) { ctx.beginPath(); ctx.arc(x + dx * r, y + dy * r, r * 0.17, 0, 6.2832); ctx.fill(); }
      ctx.beginPath(); ctx.ellipse(x, y + r * 0.3, r * 0.4, r * 0.3, 0, 0, 6.2832); ctx.fill(); break;
    }
    case 'rc': {
      ctx.fillStyle = '#e8d9a8'; ctx.beginPath(); ctx.rect(x - r * 0.75, y - r, r * 1.5, r * 2); ctx.fill(); ctx.stroke(); ctx.fillStyle = '#6a4a10';
      ctx.fillRect(x - r * 0.45, y - r * 0.6, r * 0.9, r * 0.2); ctx.fillRect(x - r * 0.45, y - r * 0.15, r * 0.9, r * 0.2); ctx.fillRect(x - r * 0.45, y + r * 0.3, r * 0.6, r * 0.2); break;
    }
    default: circle('#aaa');
  }
  ctx.restore();
}
