/*
  mi-cuenta.js - Panel del cliente (mi-cuenta.html)
  --------------------------------------------------
  1. Protege la página: solo CLIENTE. Sin sesión regresa a acceso-clientes.html.
  2. Hace funcionar el botón "Cerrar Sesión".
  3. Llena los datos del cliente con GET /api/auth/yo.
*/

const SEXOS = { F: "Femenino", M: "Masculino", N: "Prefiero no decirlo" };

// Escribe un texto en el elemento con ese id (si existe). Vacío -> "-".
function poner(id, texto) {
  const el = document.getElementById(id);
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

(async () => {
  // 1. Proteger
  const u = await Sesion.proteger(["CLIENTE"], "acceso-clientes.html");
  if (!u) return;   // ya se está regresando al acceso

  // 2. Cerrar sesión
  document.getElementById("btn-cerrar-sesion").addEventListener("click", (evento) => {
    evento.preventDefault();
    Sesion.salir();
  });

  // 3. Llenar datos (u viene de /api/auth/yo)
  poner("cliente-nombre", u.nombre);
  poner("cliente-desde", fechaLarga(u.creado_en));
  poner("cliente-puntos", Number(u.puntos_saldo ?? u.puntos ?? 0).toLocaleString("es-MX"));

  poner("cliente-nombre-completo", [u.nombre, u.apellidos].filter(Boolean).join(" "));
  poner("cliente-correo", u.correo);
  poner("cliente-telefono", u.telefono);
  poner("cliente-nacimiento", fechaLarga(u.fecha_nacimiento));
  poner("cliente-sexo", SEXOS[u.sexo]);

  // Insignia: correo confirmado o pendiente
  const insignia = document.getElementById("cliente-correo-estado");
  if (insignia && u.correo_verificado !== undefined) {
    const confirmado = Boolean(u.correo_verificado);
    insignia.textContent = confirmado ? "Confirmado" : "Sin confirmar";
    insignia.classList.add(confirmado ? "cuenta-insignia-ok" : "cuenta-insignia-pendiente");
  }
})();