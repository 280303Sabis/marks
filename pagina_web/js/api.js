/*
  api.js - Conexión de la página web con la API de MARK'S
  ---------------------------------------------------------
  Todas las páginas usan la función api() para pedir o mandar datos.
  Se encarga de:
    - Armar la dirección completa (API_URL + ruta).
    - Mandar los datos en formato JSON.
    - Agregar el token de la sesión (para rutas protegidas).
    - Convertir los errores en mensajes claros en español.

  Ejemplo:
    const datos = await api("/auth/login", { metodo: "POST", datos: {...}, conToken: false });
*/

// Dirección de la API. Si la API se publica en internet, solo se cambia aquí.
const API_URL = "http://127.0.0.1:5000/api";

// Error con información extra: el código de estado (401, 423...) y la respuesta completa.
class ErrorApi extends Error {
  constructor(mensaje, estado, datos) {
    super(mensaje);
    this.estado = estado;    // 0 = no hubo conexión con el servidor
    this.datos = datos || {};
  }
}

async function api(ruta, opciones = {}) {
  const { metodo = "GET", datos = null, conToken = true } = opciones;

  // 1. Encabezados
  const encabezados = { "Accept": "application/json" };
  if (datos !== null) {
    encabezados["Content-Type"] = "application/json";
  }
  if (conToken) {
    const token = Sesion.token();
    if (token) {
      encabezados["Authorization"] = "Bearer " + token;
    }
  }

  // 2. Petición
  let respuesta;
  try {
    respuesta = await fetch(API_URL + ruta, {
      method: metodo,
      headers: encabezados,
      body: datos !== null ? JSON.stringify(datos) : undefined,
    });
  } catch (e) {
    throw new ErrorApi("No se pudo conectar con el servidor. Revisa que la API esté encendida.", 0);
  }

  // 3. Leer la respuesta (si no es JSON, queda vacía)
  let cuerpo = {};
  try {
    cuerpo = await respuesta.json();
  } catch (e) {
    cuerpo = {};
  }

  // 4. Errores
  if (!respuesta.ok) {
    // La sesión ya no es válida (token vencido o cerrado en otro lado): regresar al login.
    if (respuesta.status === 401 && conToken && Sesion.token()) {
      Sesion.cerrar();
      location.replace("index.html?sesion=expirada");
    }
    throw new ErrorApi(cuerpo.error || "Ocurrió un error (" + respuesta.status + ")",
                       respuesta.status, cuerpo);
  }

  return cuerpo;
}