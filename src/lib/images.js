// Image processing — Option B from our discussion.
// We produce two versions of each photo:
//   - thumb: 240px max dimension, 78% JPEG quality (~15-25 KB)
//     Used in lists where speed matters more than detail.
//   - full:  1200px max dimension, 85% JPEG quality (~80-200 KB)
//     Used when the user taps a photo to view it large.
//
// Both are stored as data URLs in IndexedDB. Total per product
// is roughly 100-225 KB, so 30-50 products fits comfortably in
// the hundreds-of-MB that IndexedDB allows.

const resize = (img, maxDim, quality) => {
  let { width, height } = img;
  if (width > height) {
    if (width > maxDim) { height = Math.round(height * (maxDim / width)); width = maxDim; }
  } else {
    if (height > maxDim) { width = Math.round(width * (maxDim / height)); height = maxDim; }
  }
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, width, height);
  ctx.drawImage(img, 0, 0, width, height);
  return canvas.toDataURL('image/jpeg', quality);
};

export const processImage = (file) => {
  return new Promise((resolve, reject) => {
    if (!file) { reject(new Error('No file')); return; }
    const reader = new FileReader();
    reader.onload = (e) => {
      const img = new Image();
      img.onload = () => {
        try {
          const thumb = resize(img, 240, 0.78);
          const full = resize(img, 1200, 0.85);
          resolve({ thumb, full });
        } catch (err) {
          reject(err);
        }
      };
      img.onerror = () => reject(new Error('Image load failed'));
      img.src = e.target.result;
    };
    reader.onerror = () => reject(new Error('File read failed'));
    reader.readAsDataURL(file);
  });
};

// Estimate a data URL's byte size (base64 = ~75% of length once header stripped)
export const dataUrlSize = (dataUrl) => {
  if (!dataUrl) return 0;
  const commaIdx = dataUrl.indexOf(',');
  const b64 = commaIdx >= 0 ? dataUrl.slice(commaIdx + 1) : dataUrl;
  return Math.round((b64.length * 3) / 4);
};
