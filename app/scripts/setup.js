// Se ejecuta solo después de `npm install`: crea .env a partir de .env.example si no existe.
const fs = require('fs');
const path = require('path');
const dest = path.join(__dirname, '..', '.env');
const src = path.join(__dirname, '..', '.env.example');
if (!fs.existsSync(dest) && fs.existsSync(src)) {
  fs.copyFileSync(src, dest);
  console.log('.env creado desde .env.example (modo MOCK activado).');
}