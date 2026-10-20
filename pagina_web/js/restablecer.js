/*
  restablecer.js - Recuperar contraseña (restablecer.html)
  ---------------------------------------------------------
  Pantalla 1: correo  -> POST /api/auth/recuperar/solicitar   {correo}
  Pantalla 2: código + nueva contraseña
                      -> POST /api/auth/recuperar/restablecer {correo, codigo, password_nueva}
  Pantalla 3: listo   -> botón para iniciar sesión

  Si se llega con ?desde=clientes, los enlaces regresan a acceso-clientes.html;
  si no, a index.html (acceso del personal).
*/

const $ = (id) => document.getElementById(id);

// ------------------------------------------------------------------
// A qué login regresar
// ------------------------------------------------------------------
const DESDE_CLIENTES = new URLSearchParams(location.search).get("desde") === "clientes";
const PAGINA_LOGIN = DESDE_CLIENTES ? "acceso-clientes.html" : "index.html";
document.querySelectorAll(".volver-login").forEach((a) => { a.href = PAGINA_LOGIN; });

// ------------------------------------------------------------------
// Utilidades
// ------------------------------------------------------------------
function mostrar(caja, texto, tipo = "error", detalles = []) {
  caja.textContent = texto;
  if (detalles.length) {
    const lista = document.createElement("ul");
    detalles.forEach((d) => {
      const li = document.createElement("li");
      li.textContent = d;
      lista.appendChild(li);
    });
    caja.appendChild(lista);
  }
  caja.className = "mensaje mensaje-" + tipo;
  caja.hidden = false;
}

function ocultar(caja) {
  caja.hidden = true;
  caja.textContent = "";
}

function irA(pantalla) {
  ["paso-solicitar", "paso-cambiar", "paso-listo"].forEach((id) => {
    $(id).hidden = (id !== pantalla);
  });
}

// El código: solo números
$("rec-codigo").addEventListener("input", (e) => {
  e.target.value = e.target.value.replace(/\D/g, "");
});

let correoActual = "";   // correo al que se mandó el código

// ------------------------------------------------------------------
// Reglas de contraseña (las mismas que revisa la API en seguridad.py)
// ------------------------------------------------------------------
const REGLAS = {
  largo: (p) => p.length >= 8 && p.length <= 64,
  mayuscula: (p) => /[A-Z]/.test(p),
  minuscula: (p) => /[a-z]/.test(p),
  numero: (p) => /\d/.test(p),
  simbolo: (p) => /[^A-Za-z0-9]/.test(p),
  correo: (p, correo) => {
    const usuario = (correo.split("@")[0] || "").toLowerCase();
    return !(usuario.length >= 4 && p.toLowerCase().includes(usuario));
  },
};

function revisarReglas() {
  const p = $("rec-password").value;
  let todas = true;
  document.querySelectorAll("#reglas-password li").forEach((li) => {
    const cumple = p.length > 0 && REGLAS[li.dataset.regla](p, correoActual);
    li.classList.toggle("cumple", cumple);
    if (!cumple) todas = false;
  });
  return todas;
}

$("rec-password").addEventListener("input", revisarReglas);

// ------------------------------------------------------------------
// Botón "Reenviar código": se desactiva 60 segundos
// ------------------------------------------------------------------
let temporizador = null;

function esperarReenvio(segundos) {
  const boton = $("btn-reenviar");
  clearInterval(temporizador);
  boton.disabled = true;
  let restantes = segundos;
  boton.textContent = `Reenviar código (${restantes})`;
  temporizador = setInterval(() => {
    restantes--;
    if (restantes <= 0) {
      clearInterval(temporizador);
      boton.disabled = false;
      boton.textContent = "Reenviar código";
    } else {
      boton.textContent = `Reenviar código (${restantes})`;
    }
  }, 1000);
}

// Pide el código a la API. Regresa el mensaje (siempre el mismo, exista o no el correo).
async function pedirCodigo(correo) {
  const r = await api("/auth/recuperar/solicitar", {
    metodo: "POST",
    datos: { correo },
    conToken: false,
  });
  return r.mensaje;
}

// ------------------------------------------------------------------
// PANTALLA 1: pedir código
// ------------------------------------------------------------------
$("form-solicitar").addEventListener("submit", async (evento) => {
  evento.preventDefault();
  const caja = $("solicitar-mensaje");
  ocultar(caja);

  const correo = $("rec-correo").value.trim().toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]{2,}$/.test(correo)) {
    return mostrar(caja, "Escribe un correo válido.");
  }

  const boton = $("btn-solicitar");
  boton.disabled = true;
  boton.textContent = "Enviando...";
  try {
    const mensaje = await pedirCodigo(correo);
    correoActual = correo;
    $("rec-correo-texto").textContent = correo;
    irA("paso-cambiar");
    mostrar($("cambiar-mensaje"), mensaje, "info");
    esperarReenvio(60);
    revisarReglas();
    $("rec-codigo").focus();
  } catch (e) {
    mostrar(caja, e.message);
  } finally {
    boton.disabled = false;
    boton.textContent = "Enviar código";
  }
});

// ------------------------------------------------------------------
// PANTALLA 2: código y nueva contraseña
// ------------------------------------------------------------------
$("btn-reenviar").addEventListener("click", async () => {
  const caja = $("cambiar-mensaje");
  esperarReenvio(60);
  try {
    mostrar(caja, await pedirCodigo(correoActual), "info");
  } catch (e) {
    mostrar(caja, e.message);
  }
});

$("btn-otro-correo").addEventListener("click", () => {
  clearInterval(temporizador);
  $("btn-reenviar").disabled = false;
  $("btn-reenviar").textContent = "Reenviar código";
  ["rec-codigo", "rec-password", "rec-password2"].forEach((id) => { $(id).value = ""; });
  ocultar($("cambiar-mensaje"));
  irA("paso-solicitar");
  $("rec-correo").focus();
});

$("form-cambiar").addEventListener("submit", async (evento) => {
  evento.preventDefault();
  const caja = $("cambiar-mensaje");
  ocultar(caja);

  const codigo = $("rec-codigo").value.trim();
  const nueva = $("rec-password").value;

  if (!/^\d{6}$/.test(codigo)) return mostrar(caja, "El código tiene 6 dígitos.");
  if (!revisarReglas()) return mostrar(caja, "Tu nueva contraseña todavía no cumple todas las reglas.");
  if (nueva !== $("rec-password2").value) return mostrar(caja, "Las contraseñas no coinciden.");

  const boton = $("btn-cambiar");
  boton.disabled = true;
  boton.textContent = "Actualizando...";
  try {
    const r = await api("/auth/recuperar/restablecer", {
      metodo: "POST",
      datos: { correo: correoActual, codigo, password_nueva: nueva },
      conToken: false,
    });

    // Las sesiones abiertas de esa cuenta ya no sirven: se borra la de este navegador.
    Sesion.cerrar();
    clearInterval(temporizador);
    $("listo-mensaje").textContent = r.mensaje;
    irA("paso-listo");

  } catch (e) {
    mostrar(caja, e.message, "error", e.datos.detalles || []);
  } finally {
    boton.disabled = false;
    boton.textContent = "Actualizar Contraseña";
  }
});