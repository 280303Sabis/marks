/*
  aviso-privacidad.js - Página pública del Aviso de Privacidad (aviso-privacidad.html)
  -------------------------------------------------------------------------------------
  Pide el texto vigente a GET /api/legal/aviso-privacidad (no necesita sesión)
  y lo acomoda en la página: título, versión y fecha, y sus secciones.
*/

const $ = (id) => document.getElementById(id);

// "2026-10-10" -> "10 de octubre de 2026" (si no es fecha, se deja igual)
function fechaLarga(texto) {
  if (!/^\d{4}-\d{2}-\d{2}/.test(texto || "")) return texto || "";
  const [anio, mes, dia] = texto.slice(0, 10).split("-").map(Number);
  return new Date(anio, mes - 1, dia).toLocaleDateString("es-MX", {
    day: "numeric", month: "long", year: "numeric",
  });
}

// Crea un elemento con su texto y lo agrega al contenedor.
function agregar(contenedor, etiqueta, texto) {
  const el = document.createElement(etiqueta);
  el.textContent = texto;
  contenedor.appendChild(el);
}

// Acomoda el aviso sin importar si viene en secciones o como un solo texto.
function pintarAviso(d) {
  if (d.titulo) {
    $("aviso-titulo").textContent = d.titulo;
    document.title = "MARK'S - " + d.titulo;
  }

  const fecha = d.fecha || d.fecha_actualizacion || d.vigente_desde;
  const meta = [
    d.version ? "Versión " + d.version : "",
    fecha ? "vigente desde el " + fechaLarga(fecha) : "",
  ].filter(Boolean).join(", ");
  $("aviso-meta").textContent = meta;

  const cont = $("aviso-contenido");
  cont.textContent = "";

  if (Array.isArray(d.secciones)) {
    d.secciones.forEach((s) => {
      const seccion = document.createElement("section");
      if (typeof s === "string") {
        agregar(seccion, "p", s);
      } else {
        if (s.titulo) agregar(seccion, "h2", s.titulo);
        const t = s.texto || s.contenido || s.cuerpo || s.parrafos;
        if (Array.isArray(t)) t.forEach((x) => agregar(seccion, "p", x));
        else if (t) agregar(seccion, "p", t);
      }
      cont.appendChild(seccion);
    });
  } else if (typeof d.texto === "string") {
    d.texto.split(/\n\s*\n/).forEach((p) => agregar(cont, "p", p));
  } else {
    agregar(cont, "pre", JSON.stringify(d, null, 2));
  }
}

(async () => {
  try {
    pintarAviso(await api("/legal/aviso-privacidad", { conToken: false }));
  } catch (e) {
    const cont = $("aviso-contenido");
    cont.textContent = "";
    const p = document.createElement("p");
    p.className = "mensaje mensaje-error";
    p.textContent = e.message;
    cont.appendChild(p);
  }
})();