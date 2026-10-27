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

// Dirección de la API publicada en Render (la misma que usa la app).
// Para probar con la API de TU compu sin cambiar este archivo, escribe una vez
// en la consola del navegador (F12 > Console), en la página abierta con Live Server:
//     localStorage.setItem("marks_api_url", "http://127.0.0.1:5000/api")
// y recarga. Para regresar a Render:  localStorage.removeItem("marks_api_url")
const API_URL = localStorage.getItem("marks_api_url") || "https://marks-api-xw78.onrender.com/api";
if (API_URL !== "https://marks-api-xw78.onrender.com/api") {
  console.info("MARK'S: usando la API de " + API_URL);
}

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
    throw new ErrorApi("No se pudo conectar con el servidor. Si la API estaba dormida, espera un minuto y recarga la página.", 0);
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
    // La sesión ya no es válida (token vencido o cerrado en otro lado):
    // regresar a la página de acceso por la que entró.
    if (respuesta.status === 401 && conToken && Sesion.token()) {
      const acceso = Sesion.paginaAcceso();
      Sesion.cerrar();
      location.replace(acceso + "?sesion=expirada");
    }
    throw new ErrorApi(cuerpo.error || "Ocurrió un error (" + respuesta.status + ")",
                       respuesta.status, cuerpo);
  }

  return cuerpo;
}