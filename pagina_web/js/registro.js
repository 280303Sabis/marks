/*
  registro.js - Crear cuenta de cliente (registro.html)
  ------------------------------------------------------
  Pantalla 1: datos -> POST /api/auth/registro (crea CLIENTE y regresa token)
  Pantalla 2: código -> POST /api/auth/correo/enviar-codigo
                        POST /api/auth/correo/confirmar
  Al terminar abre mi-cuenta.html.
*/

const $ = (id) => document.getElementById(id);
const EDAD_MINIMA = 18;

// ------------------------------------------------------------------
// Utilidades
// ------------------------------------------------------------------

// Muestra un mensaje en una caja. detalles = lista de errores (opcional).
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

// Fecha a texto "AAAA-MM-DD" (formato del input date y de la API)
function aTexto(fecha) {
  const m = String(fecha.getMonth() + 1).padStart(2, "0");
  const d = String(fecha.getDate()).padStart(2, "0");
  return `${fecha.getFullYear()}-${m}-${d}`;
}

function edad(textoFecha) {
  const [a, m, d] = textoFecha.split("-").map(Number);
  const hoy = new Date();
  let anios = hoy.getFullYear() - a;
  if (hoy.getMonth() + 1 < m || (hoy.getMonth() + 1 === m && hoy.getDate() < d)) anios--;
  return anios;
}

// ------------------------------------------------------------------
// Si ya hay sesión de cliente, no tiene caso registrarse
// ------------------------------------------------------------------
const yaConectado = Sesion.usuario();
if (Sesion.token() && yaConectado && yaConectado.rol === "CLIENTE") {
  location.replace("mi-cuenta.html");
}

// Límites del calendario: mínimo 18 años, máximo 120
const hoy = new Date();
$("reg-nacimiento").max = aTexto(new Date(hoy.getFullYear() - EDAD_MINIMA, hoy.getMonth(), hoy.getDate()));
$("reg-nacimiento").min = aTexto(new Date(hoy.getFullYear() - 120, hoy.getMonth(), hoy.getDate()));

// Teléfono y código: solo números
["reg-telefono", "reg-codigo"].forEach((id) => {
  $(id).addEventListener("input", (e) => {
    e.target.value = e.target.value.replace(/\D/g, "");
  });
});

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
  const p = $("reg-password").value;
  const correo = $("reg-correo").value.trim();
  let todas = true;
  document.querySelectorAll("#reglas-password li").forEach((li) => {
    const cumple = p.length > 0 && REGLAS[li.dataset.regla](p, correo);
    li.classList.toggle("cumple", cumple);
    if (!cumple) todas = false;
  });
  return todas;
}

$("reg-password").addEventListener("input", revisarReglas);
$("reg-correo").addEventListener("input", revisarReglas);

// ------------------------------------------------------------------
// Aviso de Privacidad (ventana)
// ------------------------------------------------------------------
let avisoCargado = false;

function agregar(contenedor, etiqueta, texto, clase) {
  const el = document.createElement(etiqueta);
  el.textContent = texto;
  if (clase) el.className = clase;
  contenedor.appendChild(el);
}

// Acomoda el aviso sin importar cómo venga organizado desde la API.
function pintarAviso(d) {
  const cont = $("aviso-contenido");
  cont.textContent = "";
  if (d.titulo) $("aviso-titulo").textContent = d.titulo;

  const fecha = d.fecha || d.fecha_actualizacion || d.vigente_desde;
  const meta = [d.version ? "Versión " + d.version : "", fecha || ""].filter(Boolean).join(" - ");
  if (meta) agregar(cont, "p", meta, "aviso-meta");

  if (Array.isArray(d.secciones)) {
    d.secciones.forEach((s) => {
      if (typeof s === "string") { agregar(cont, "p", s); return; }
      if (s.titulo) agregar(cont, "h3", s.titulo);
      const t = s.texto || s.contenido || s.cuerpo || s.parrafos;
      if (Array.isArray(t)) t.forEach((x) => agregar(cont, "p", x));
      else if (t) agregar(cont, "p", t);
    });
  } else if (typeof d.texto === "string") {
    d.texto.split(/\n\s*\n/).forEach((p) => agregar(cont, "p", p));
  } else {
    agregar(cont, "pre", JSON.stringify(d, null, 2));
  }
}

$("ver-aviso").addEventListener("click", async (e) => {
  e.preventDefault();
  $("aviso-dialogo").showModal();
  if (avisoCargado) return;
  try {
    pintarAviso(await api("/legal/aviso-privacidad", { conToken: false }));
    avisoCargado = true;
  } catch (err) {
    $("aviso-contenido").textContent = err.message;
  }
});

$("aviso-cerrar").addEventListener("click", () => $("aviso-dialogo").close());
$("aviso-aceptar").addEventListener("click", () => {
  $("reg-privacidad").checked = true;
  $("aviso-dialogo").close();
});

// ------------------------------------------------------------------
// PANTALLA 1: enviar datos
// ------------------------------------------------------------------
$("form-registro").addEventListener("submit", async (evento) => {
  evento.preventDefault();
  const caja = $("registro-mensaje");
  ocultar(caja);

  const datos = {
    nombre: $("reg-nombre").value.trim(),
    apellidos: $("reg-apellidos").value.trim(),
    correo: $("reg-correo").value.trim().toLowerCase(),
    telefono: $("reg-telefono").value.trim(),
    fecha_nacimiento: $("reg-nacimiento").value,
    sexo: $("reg-sexo").value,
    password: $("reg-password").value,
    acepta_privacidad: $("reg-privacidad").checked,
  };

  // Revisiones rápidas antes de molestar a la API
  if (datos.nombre.length < 2) return mostrar(caja, "Escribe tu nombre.");
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]{2,}$/.test(datos.correo)) return mostrar(caja, "Escribe un correo válido.");
  if (datos.telefono && datos.telefono.length !== 10) return mostrar(caja, "El teléfono debe tener 10 dígitos.");
  if (!datos.fecha_nacimiento) return mostrar(caja, "Escribe tu fecha de nacimiento.");
  if (edad(datos.fecha_nacimiento) < EDAD_MINIMA) {
    return mostrar(caja, `Debes tener al menos ${EDAD_MINIMA} años para crear una cuenta.`);
  }
  if (!datos.sexo) return mostrar(caja, "Selecciona una opción en sexo.");
  if (!revisarReglas()) return mostrar(caja, "Tu contraseña todavía no cumple todas las reglas.");
  if (datos.password !== $("reg-password2").value) return mostrar(caja, "Las contraseñas no coinciden.");
  if (!datos.acepta_privacidad) return mostrar(caja, "Debes aceptar el Aviso de Privacidad.");

  const boton = $("btn-registrar");
  boton.disabled = true;
  boton.textContent = "Creando cuenta...";
  try {
    const r = await api("/auth/registro", { metodo: "POST", datos, conToken: false });

    // La cuenta ya existe y la sesión queda iniciada (entra por el acceso de clientes)
    Sesion.guardar(r.token, r.usuario, "acceso-clientes.html");
    irAPasoCodigo(datos.correo);

  } catch (e) {
    mostrar(caja, e.message, "error", e.datos.detalles || []);
  } finally {
    boton.disabled = false;
    boton.textContent = "Crear cuenta";
  }
});

// ------------------------------------------------------------------
// PANTALLA 2: código de confirmación
// ------------------------------------------------------------------
let temporizador = null;

function irAPasoCodigo(correo) {
  $("paso-datos").hidden = true;
  $("paso-codigo").hidden = false;
  $("codigo-correo").textContent = correo;
  window.scrollTo({ top: 0, behavior: "smooth" });
  enviarCodigo();
}

// Desactiva "Reenviar código" unos segundos para no saturar el correo.
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

async function enviarCodigo() {
  const caja = $("codigo-mensaje");
  mostrar(caja, "Enviando código...", "info");
  esperarReenvio(60);
  try {
    const r = await api("/auth/correo/enviar-codigo", { metodo: "POST" });
    mostrar(caja, r.mensaje, "info");
  } catch (e) {
    mostrar(caja, e.message);
  }
}

$("btn-reenviar").addEventListener("click", enviarCodigo);

$("form-codigo").addEventListener("submit", async (evento) => {
  evento.preventDefault();
  const caja = $("codigo-mensaje");
  const codigo = $("reg-codigo").value.trim();

  if (!/^\d{6}$/.test(codigo)) return mostrar(caja, "El código tiene 6 dígitos.");

  const boton = $("btn-confirmar");
  boton.disabled = true;
  boton.textContent = "Confirmando...";
  try {
    const r = await api("/auth/correo/confirmar", { metodo: "POST", datos: { codigo } });
    mostrar(caja, r.mensaje + ". Abriendo tu cuenta...", "info");
    setTimeout(() => location.replace("mi-cuenta.html"), 1200);
  } catch (e) {
    mostrar(caja, e.message);
    boton.disabled = false;
    boton.textContent = "Confirmar correo";
  }
});