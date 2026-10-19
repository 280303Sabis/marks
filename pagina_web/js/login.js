/*
  login.js - Inicio de sesión (sirve para index.html y acceso-clientes.html)
  ---------------------------------------------------------------------------
  Cada formulario indica en su HTML cómo debe comportarse:
    data-roles="ADMIN"              roles que pueden entrar (separados por coma)
    data-destino="dashboard.html"   página que se abre al entrar
    data-mensaje-rol="..."          mensaje si la cuenta es de otro tipo

  1. Si ya hay una sesión con un rol permitido, entra directo al destino.
  2. Al enviar, manda correo y contraseña a POST /api/auth/login.
  3. Solo deja entrar a los roles permitidos.
  4. Muestra los errores de la API (contraseña incorrecta, cuenta bloqueada...).
*/

const formulario = document.getElementById("form-login");
const campoCorreo = document.getElementById("email");
const campoPassword = document.getElementById("password");
const boton = document.getElementById("btn-ingresar");
const cajaMensaje = document.getElementById("login-mensaje");

// Configuración leída del HTML
const ROLES_PERMITIDOS = (formulario.dataset.roles || "")
  .split(",").map((r) => r.trim()).filter(Boolean);
const DESTINO = formulario.dataset.destino;
const MENSAJE_ROL = formulario.dataset.mensajeRol
  || "Esta cuenta no tiene acceso a esta sección.";
// Nombre de esta página (index.html o acceso-clientes.html): aquí se regresa al salir.
const PAGINA_ACCESO = location.pathname.split("/").pop() || "index.html";

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
const TEXTO_BOTON = boton.textContent;
function cargando(activo) {
  boton.disabled = activo;
  boton.textContent = activo ? "Ingresando..." : TEXTO_BOTON;
}

// 1. Si ya hay sesión con un rol permitido, no tiene caso volver a iniciar sesión.
const usuarioActual = Sesion.usuario();
if (Sesion.token() && usuarioActual && ROLES_PERMITIDOS.includes(usuarioActual.rol)) {
  location.replace(DESTINO);
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

    // 3. Solo los roles permitidos en esta página
    if (!ROLES_PERMITIDOS.includes(respuesta.usuario.rol)) {
      mostrarMensaje(MENSAJE_ROL);
      campoPassword.value = "";
      return;
    }

    Sesion.guardar(respuesta.token, respuesta.usuario, PAGINA_ACCESO);
    location.replace(DESTINO);

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