/*
  mi-cuenta.js - Panel del cliente (mi-cuenta.html)
  --------------------------------------------------
  1. Protege la página: solo CLIENTE. Sin sesión regresa a acceso-clientes.html.
  2. Hace funcionar el botón "Cerrar sesión".
  3. Muestra los datos del cliente (GET /api/auth/yo).
  4. Editar mis datos           (PUT  /api/cuenta/perfil).
  5. Cambiar contraseña         (POST /api/cuenta/cambiar-password).
*/

const $ = (id) => document.getElementById(id);
const SEXOS = { F: "Femenino", M: "Masculino", N: "Prefiero no decirlo" };
const EDAD_MINIMA = 18;

let usuario = null;   // datos actuales del cliente

// ------------------------------------------------------------------
// Utilidades
// ------------------------------------------------------------------

// Escribe un texto en el elemento con ese id (si existe). Vacío -> "-".
function poner(id, texto) {
  const el = $(id);
  if (el) {
    el.textContent = (texto === null || texto === undefined || texto === "") ? "-" : texto;
  }
}

// "2026-10-07T14:30:00" -> "7 de octubre de 2026"
function fechaLarga(isoTexto) {
  if (!isoTexto) return "";
  const [anio, mes, dia] = isoTexto.slice(0, 10).split("-").map(Number);
  // Se arma la fecha con año, mes y día para que no se recorra un día por la zona horaria.
  return new Date(anio, mes - 1, dia).toLocaleDateString("es-MX", {
    day: "numeric", month: "long", year: "numeric",
  });
}

// "Sabina Isabel" + "Ortega González" -> "SO"
function iniciales(nombre, apellidos) {
  const primera = (texto) => (texto || "").trim().charAt(0).toUpperCase();
  return (primera(nombre) + primera(apellidos)) || "M";
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

// ------------------------------------------------------------------
// 3. Mostrar datos
// ------------------------------------------------------------------
function pintarDatos(u) {
  poner("cliente-iniciales", iniciales(u.nombre, u.apellidos));
  poner("cliente-nombre", u.nombre);
  poner("cliente-desde", fechaLarga(u.creado_en));
  poner("cliente-puntos", Number(u.puntos_saldo ?? u.puntos ?? 0).toLocaleString("es-MX"));

  poner("cliente-nombre-completo", [u.nombre, u.apellidos].filter(Boolean).join(" "));
  poner("cliente-correo", u.correo);
  poner("cliente-telefono", u.telefono);
  poner("cliente-nacimiento", fechaLarga(u.fecha_nacimiento));
  poner("cliente-sexo", SEXOS[u.sexo]);

  // Insignia: correo confirmado o pendiente
  const insignia = $("cliente-correo-estado");
  if (insignia && u.correo_verificado !== undefined) {
    const confirmado = Boolean(u.correo_verificado);
    insignia.textContent = confirmado ? "Confirmado" : "Sin confirmar";
    insignia.classList.remove("cuenta-insignia-ok", "cuenta-insignia-pendiente");
    insignia.classList.add(confirmado ? "cuenta-insignia-ok" : "cuenta-insignia-pendiente");
  }
}

// ------------------------------------------------------------------
// 4. Editar mis datos
// ------------------------------------------------------------------
function abrirEdicion() {
  $("dat-nombre").value = usuario.nombre || "";
  $("dat-apellidos").value = usuario.apellidos || "";
  $("dat-telefono").value = usuario.telefono || "";
  $("dat-nacimiento").value = (usuario.fecha_nacimiento || "").slice(0, 10);
  $("dat-sexo").value = usuario.sexo || "";

  ocultar($("datos-mensaje"));
  ocultar($("form-datos-mensaje"));
  $("cuenta-datos-vista").hidden = true;
  $("btn-editar-datos").hidden = true;
  $("form-datos").hidden = false;
  $("dat-nombre").focus();
}

function cerrarEdicion() {
  $("form-datos").hidden = true;
  $("cuenta-datos-vista").hidden = false;
  $("btn-editar-datos").hidden = false;
}

async function guardarDatos(evento) {
  evento.preventDefault();
  const caja = $("form-datos-mensaje");
  ocultar(caja);

  const datos = {
    nombre: $("dat-nombre").value.trim(),
    apellidos: $("dat-apellidos").value.trim(),
    telefono: $("dat-telefono").value.trim(),
    fecha_nacimiento: $("dat-nacimiento").value,
    sexo: $("dat-sexo").value,
  };

  // Revisiones rápidas (la API vuelve a revisar todo)
  if (datos.nombre.length < 2) return mostrar(caja, "Escribe tu nombre.");
  if (datos.telefono && datos.telefono.length !== 10) return mostrar(caja, "El teléfono debe tener 10 dígitos.");
  if (!datos.fecha_nacimiento) return mostrar(caja, "Escribe tu fecha de nacimiento.");
  if (edad(datos.fecha_nacimiento) < EDAD_MINIMA) {
    return mostrar(caja, `Debes tener al menos ${EDAD_MINIMA} años.`);
  }
  if (!datos.sexo) return mostrar(caja, "Selecciona una opción en sexo.");

  const boton = $("btn-guardar-datos");
  boton.disabled = true;
  boton.textContent = "Guardando...";
  try {
    const r = await api("/cuenta/perfil", { metodo: "PUT", datos });

    // Actualizar la pantalla y el nombre guardado en la sesión
    Object.assign(usuario, r.usuario);
    pintarDatos(usuario);
    Sesion.guardar(Sesion.token(), { ...Sesion.usuario(), nombre: usuario.nombre }, Sesion.paginaAcceso());

    cerrarEdicion();
    mostrar($("datos-mensaje"), r.mensaje + ".", "info");
  } catch (e) {
    mostrar(caja, e.message, "error", e.datos.detalles || []);
  } finally {
    boton.disabled = false;
    boton.textContent = "Guardar cambios";
  }
}

// ------------------------------------------------------------------
// 5. Cambiar contraseña
// ------------------------------------------------------------------
// Las mismas reglas que revisa la API en seguridad.py
const REGLAS = {
  largo: (p) => p.length >= 8 && p.length <= 64,
  mayuscula: (p) => /[A-Z]/.test(p),
  minuscula: (p) => /[a-z]/.test(p),
  numero: (p) => /\d/.test(p),
  simbolo: (p) => /[^A-Za-z0-9]/.test(p),
  correo: (p, correo) => {
    const nombreCorreo = (correo.split("@")[0] || "").toLowerCase();
    return !(nombreCorreo.length >= 4 && p.toLowerCase().includes(nombreCorreo));
  },
};

function revisarReglas() {
  const p = $("pass-nueva").value;
  const correo = (usuario && usuario.correo) || "";
  let todas = true;
  document.querySelectorAll("#reglas-password li").forEach((li) => {
    const cumple = p.length > 0 && REGLAS[li.dataset.regla](p, correo);
    li.classList.toggle("cumple", cumple);
    if (!cumple) todas = false;
  });
  return todas;
}

async function cambiarPassword(evento) {
  evento.preventDefault();
  const caja = $("password-mensaje");
  ocultar(caja);

  const actual = $("pass-actual").value;
  const nueva = $("pass-nueva").value;

  if (!actual) return mostrar(caja, "Escribe tu contraseña actual.");
  if (!revisarReglas()) return mostrar(caja, "Tu nueva contraseña todavía no cumple todas las reglas.");
  if (nueva !== $("pass-nueva2").value) return mostrar(caja, "Las contraseñas nuevas no coinciden.");
  if (nueva === actual) return mostrar(caja, "La nueva contraseña debe ser diferente a la actual.");

  const boton = $("btn-cambiar-password");
  boton.disabled = true;
  boton.textContent = "Cambiando...";
  try {
    const r = await api("/cuenta/cambiar-password", {
      metodo: "POST",
      datos: { password_actual: actual, password_nueva: nueva },
    });

    // La API cerró las demás sesiones y entregó un token nuevo para esta.
    Sesion.guardar(r.token, Sesion.usuario(), Sesion.paginaAcceso());

    $("form-password").reset();
    revisarReglas();
    mostrar(caja, r.mensaje + ".", "info");
  } catch (e) {
    mostrar(caja, e.message, "error", e.datos.detalles || []);
    $("pass-actual").value = "";
  } finally {
    boton.disabled = false;
    boton.textContent = "Cambiar contraseña";
  }
}

// ------------------------------------------------------------------
// Inicio
// ------------------------------------------------------------------
(async () => {
  // 1. Proteger
  const u = await Sesion.proteger(["CLIENTE"], "acceso-clientes.html");
  if (!u) return;   // ya se está regresando al acceso
  usuario = u;

  // 2. Cerrar sesión
  $("btn-cerrar-sesion").addEventListener("click", (evento) => {
    evento.preventDefault();
    Sesion.salir();
  });

  // 3. Datos
  pintarDatos(usuario);

  // 4. Editar mis datos
  const hoy = new Date();
  $("dat-nacimiento").max = aTexto(new Date(hoy.getFullYear() - EDAD_MINIMA, hoy.getMonth(), hoy.getDate()));
  $("dat-nacimiento").min = aTexto(new Date(hoy.getFullYear() - 120, hoy.getMonth(), hoy.getDate()));
  $("dat-telefono").addEventListener("input", (e) => {
    e.target.value = e.target.value.replace(/\D/g, "");
  });
  $("btn-editar-datos").addEventListener("click", abrirEdicion);
  $("btn-cancelar-datos").addEventListener("click", cerrarEdicion);
  $("form-datos").addEventListener("submit", guardarDatos);

  // 5. Cambiar contraseña
  $("pass-nueva").addEventListener("input", revisarReglas);
  $("form-password").addEventListener("submit", cambiarPassword);
})();