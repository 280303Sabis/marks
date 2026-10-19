/*
  login.js - Inicio de sesión del portal (index.html)
  ----------------------------------------------------
  1. Si ya hay una sesión de ADMIN abierta, entra directo al dashboard.
  2. Al tocar "Ingresar" manda correo y contraseña a POST /api/auth/login.
  3. Solo deja entrar a usuarios con rol ADMIN.
  4. Muestra los errores de la API (contraseña incorrecta, cuenta bloqueada...).
*/

const ROLES_PORTAL = ["ADMIN"];

const formulario = document.getElementById("form-login");
const campoCorreo = document.getElementById("email");
const campoPassword = document.getElementById("password");
const boton = document.getElementById("btn-ingresar");
const cajaMensaje = document.getElementById("login-mensaje");

// Muestra un mensaje arriba del botón. tipo: "error" o "info".
function mostrarMensaje(texto, tipo = "error") {
  cajaMensaje.textContent = texto;
  cajaMensaje.className = "mensaje mensaje-" + tipo;
  cajaMensaje.hidden = false;
}

function ocultarMensaje() {
  cajaMensaje.hidden = true;
  cajaMensaje.textContent = "";
}

// Bloquea el botón mientras se espera la respuesta (evita doble clic).
function cargando(activo) {
  boton.disabled = activo;
  boton.textContent = activo ? "Ingresando..." : "Ingresar";
}

// 1. Si ya hay sesión de ADMIN, no tiene caso volver a iniciar sesión.
const usuarioActual = Sesion.usuario();
if (Sesion.token() && usuarioActual && ROLES_PORTAL.includes(usuarioActual.rol)) {
  location.replace("dashboard.html");
}

// Aviso cuando la sesión se cerró porque el token ya no era válido.
if (new URLSearchParams(location.search).get("sesion") === "expirada") {
  mostrarMensaje("Tu sesión terminó. Vuelve a iniciar sesión.", "info");
}

// 2. Enviar el formulario
formulario.addEventListener("submit", async (evento) => {
  evento.preventDefault();   // evita que el formulario recargue la página
  ocultarMensaje();

  const correo = campoCorreo.value.trim().toLowerCase();
  const password = campoPassword.value;

  if (!correo || !password) {
    mostrarMensaje("Escribe tu correo y tu contraseña.");
    return;
  }

  cargando(true);
  try {
    const respuesta = await api("/auth/login", {
      metodo: "POST",
      datos: { correo, password },
      conToken: false,
    });

    // 3. Solo administradores
    if (!ROLES_PORTAL.includes(respuesta.usuario.rol)) {
      mostrarMensaje("Esta cuenta no tiene acceso al portal de administración. " +
                     "Si eres cliente, usa la app MARK'S.");
      campoPassword.value = "";
      return;
    }

    Sesion.guardar(respuesta.token, respuesta.usuario);
    location.replace("dashboard.html");

  } catch (e) {
    // 4. Errores de la API
    let texto = e.message;
    if (e.estado === 401 && e.datos.intentos_restantes !== undefined) {
      texto += ". Te quedan " + e.datos.intentos_restantes + " intento(s).";
    }
    mostrarMensaje(texto);
    campoPassword.value = "";
    campoPassword.focus();
  } finally {
    cargando(false);
  }
});