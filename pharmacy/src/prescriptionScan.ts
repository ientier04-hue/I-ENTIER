export const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
export function scanImage(base64: string) {
  if (!base64 || base64.length > Math.ceil(MAX_IMAGE_BYTES / 3) * 4 || !/^[A-Za-z0-9+/]+={0,2}$/.test(base64))
    throw new Error('Image invalide ou trop volumineuse (10 Mo maximum).');
  const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0));
  if (bytes.length > MAX_IMAGE_BYTES) throw new Error('Image trop volumineuse (10 Mo maximum).');
  const mime = bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255 ? 'image/jpeg'
    : bytes[0] === 137 && bytes[1] === 80 && bytes[2] === 78 && bytes[3] === 71 ? 'image/png'
    : String.fromCharCode(...bytes.slice(0,4)) === 'RIFF' && String.fromCharCode(...bytes.slice(8,12)) === 'WEBP' ? 'image/webp' : null;
  if (!mime) throw new Error('Choisissez une image JPEG, PNG ou WebP.');
  return {bytes, mime, extension:mime === 'image/jpeg' ? 'jpg' : mime.split('/')[1], uri:`data:${mime};base64,${base64}`};
}
export function cleanTranscription(text: string) {
  // Preserve medication names, punctuation, units and line breaks verbatim.
  return text.replace(/\r\n?/g,'\n').replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g,'').trim().slice(0,20000);
}
