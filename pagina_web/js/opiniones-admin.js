/*
  opiniones-admin.js - Moderación de opiniones del panel (PASO W11)
  ------------------------------------------------------------------
  Lo usa opiniones.html.
  1. Protege la página: sin sesión de ADMIN regresa a index.html.
  2. Lista las opiniones (primero las reportadas) con sus fotos y reportes.
  3. Ocultar (con motivo), volver a mostrar y "No hay problema"
     (marca los reportes como revisados y la deja publicada).
  4. Las fotos se piden con el token (también las de opiniones ocultas)
     y se ven en grande al tocarlas.

  Rutas de la API que usa:
    GET  /admin/opiniones?filtro=&producto_id=&estrellas=&buscar=
    POST /admin/opiniones/<id>/ocultar | /mostrar | /revisar
    GET  /admin/opiniones/fotos/<archivo>
*/

// ---------- Ayudantes ----------
const $ = (id) => document.getElementById(id);

function texto(t) {
  const d = document.createElement("div");
  d.textContent = t == null ? "" : String(t);
  return d.innerHTML;
}

function iniciales(nombre) {
  const cortas = ["de", "del", "la", "las", "los", "y"];
  const palabras = String(nombre || "").split(/\s+/).filter((p) => p && !cortas.includes(p.toLowerCase()));
  return palabras.slice(0, 2).map((p) => p[0].toUpperCase()).join("") || "M";
}

// "2026-10-27 14:32" -> "27 oct 2026, 14:32"
function fechaHora(textoFecha) {
  if (!textoFecha) return "";
  const [dia, hora] = textoFecha.split(" ");
  const f = new Date(dia + "T12:00:00").toLocaleDateString("es-MX", { day: "numeric", month: "short", year: "numeric" });
  return f.replace(".", "") + (hora ? ", " + hora : "");
}

function estrellas(n) {
  let html = "";
  for (let i = 1; i <= 5; i++) {
    html += `<i class="ph-fill ph-star${i > n ? " apagada" : ""}" aria-hidden="true"></i>`;
  }
  return `<span class="opa-estrellas" title="${n} de 5 estrellas">${html}</span>`;
}

// ---------- Avisos ----------
function mostrarError(e) {
  const aviso = $("aviso-api");
  let mensaje = e.message || "No se pudieron cargar los datos.";
  if (e.estado === 404) {
    mensaje = "La API todavía no tiene el módulo de opiniones. Revisa que estés usando la API nueva (PASO W11).";
  }
  aviso.innerHTML = '<i class="ph ph-warning-circle" aria-hidden="true"></i><span>' + texto(mensaje) + "</span>";
  aviso.hidden = false;
  document.querySelectorAll(".opa-cargando").forEach((fila) => fila.remove());
}

function ocultarError() {
  $("aviso-api").hidden = true;
}

let esperaAvisoOk;
function mostrarOk(mensaje) {
  const aviso = $("aviso-ok");
  aviso.innerHTML = '<i class="ph ph-check-circle" aria-hidden="true"></i><span>' + texto(mensaje) + "</span>";
  aviso.hidden = false;
  clearTimeout(esperaAvisoOk);
  esperaAvisoOk = setTimeout(() => { aviso.hidden = true; }, 6000);
}

// ---------- Fotos (se piden con el token y se guardan en memoria) ----------
const fotosCargadas = {};   // url de la API -> dirección local de la imagen

async function urlFoto(url) {
  if (fotosCargadas[url]) return fotosCargadas[url];
  const respuesta = await fetch(API_URL + url, {
    headers: { Authorization: "Bearer " + Sesion.token() },
  });
  if (!respuesta.ok) throw new Error("Foto no disponible");
  fotosCargadas[url] = URL.createObjectURL(await respuesta.blob());
  return fotosCargadas[url];
}

function cargarFotos() {
  document.querySelectorAll("img[data-foto]").forEach((img) => {
    urlFoto(img.dataset.foto)
      .then((local) => { img.src = local; })
      .catch(() => { img.alt = "Foto no disponible"; });
  });
}

// ---------- Lista ----------
const TITULOS = {
  reportadas: ["Reportadas", "Primero las que tienen más reportes. Revisa cada una y decide."],
  ocultas: ["Ocultas", "No se ven en la app; solo su autor las ve. Puedes volver a mostrarlas."],
  todas: ["Todas las opiniones", "Las más recientes primero (y arriba las que tienen reportes)."],
};

let opiniones = [];

function itemOpinion(o) {
  const oculta = o.estado === "OCULTA";
  const comentario = o.comentario
    ? `<p class="opa-comentario">${texto(o.comentario)}</p>`
    : '<p class="opa-comentario vacio">Sin comentario, solo estrellas.</p>';
  const fotos = o.fotos.length
    ? `<div class="opa-fotos">${o.fotos.map((f) =>
        `<button type="button" class="opa-foto" data-ver="${texto(f.url)}" aria-label="Ver foto en grande">
           <img data-foto="${texto(f.url)}" alt="Foto de la opinión">
         </button>`).join("")}</div>`
    : "";
  const reportes = o.reportes_pendientes
    ? `<div class="opa-reportes">${o.motivos.map((m) =>
        `<span class="opa-reporte"><i class="ph ph-flag" aria-hidden="true"></i>${texto(m.motivo)}${m.veces > 1 ? " ×" + m.veces : ""}</span>`).join("")}</div>`
    : "";
  const motivoOculta = oculta
    ? `<div class="opa-motivo-oculta"><strong>Oculta:</strong> ${texto(o.motivo_oculta || "sin motivo")}${o.oculta_por ? " · por " + texto(o.oculta_por) : ""}</div>`
    : "";

  const botones = [];
  if (oculta) {
    botones.push(`<button type="button" class="cl-boton-sec" data-accion="mostrar" data-id="${o.id}"><i class="ph ph-eye" aria-hidden="true"></i>Volver a mostrar</button>`);
  } else {
    if (o.reportes_pendientes) {
      botones.push(`<button type="button" class="cl-boton-sec" data-accion="revisar" data-id="${o.id}"><i class="ph ph-check" aria-hidden="true"></i>No hay problema</button>`);
    }
    botones.push(`<button type="button" class="cl-boton-sec opa-boton-ocultar" data-accion="ocultar" data-id="${o.id}"><i class="ph ph-eye-slash" aria-hidden="true"></i>Ocultar</button>`);
  }

  return `<li class="opa-item${oculta ? " oculta" : ""}">
      <div>
        <div class="opa-cuerpo">
          <div class="opa-cabeza">
            ${estrellas(o.estrellas)}
            <span class="opa-producto">${texto(o.producto)}</span>
            <span class="opa-insignia ${oculta ? "oculta" : "publicada"}">${oculta ? "Oculta" : "Publicada"}</span>
            ${o.editada ? '<span class="opa-insignia editada">Editada</span>' : ""}
          </div>
          <div class="opa-meta">${texto(o.cliente)} · ${texto(o.correo)} · ${texto(fechaHora(o.creada_en))}</div>
          ${comentario}
          ${fotos}
        </div>
        ${reportes}
        ${motivoOculta}
      </div>
      <div class="opa-acciones">${botones.join("")}</div>
    </li>`;
}

function pintarLista(filtro) {
  const [titulo, nota] = TITULOS[filtro] || TITULOS.todas;
  $("titulo-lista").textContent = titulo;
  $("lista-nota").textContent = nota;

  if (!opiniones.length) {
    const vacios = {
      reportadas: ["check-circle", "No hay reportes pendientes", "Cuando un cliente reporte una opinión, aparecerá aquí."],
      ocultas: ["eye", "No hay opiniones ocultas", "Las que ocultes aparecerán aquí."],
      todas: ["chat-circle-text", "Sin opiniones", "Ninguna opinión coincide con los filtros."],
    };
    const [icono, t, d] = vacios[filtro] || vacios.todas;
    $("lista-opiniones").innerHTML = `<li class="opa-vacio"><i class="ph ph-${icono}" aria-hidden="true"></i><strong>${t}</strong>${d}</li>`;
    return;
  }
  $("lista-opiniones").innerHTML = opiniones.map(itemOpinion).join("");
  cargarFotos();
}

async function cargarOpiniones() {
  const filtros = new URLSearchParams({ filtro: $("filtro").value });
  if ($("filtro-producto").value) filtros.set("producto_id", $("filtro-producto").value);
  if ($("filtro-estrellas").value) filtros.set("estrellas", $("filtro-estrellas").value);
  if ($("buscar").value.trim()) filtros.set("buscar", $("buscar").value.trim());
  const r = await api("/admin/opiniones?" + filtros);

  opiniones = r.opiniones;
  const s = r.resumen;
  $("opa-pendientes").textContent = s.reportes_pendientes;
  $("opa-pendientes-nota").textContent = s.reportes_pendientes
    ? `En ${s.opiniones_reportadas} opinión${s.opiniones_reportadas === 1 ? "" : "es"}`
    : "Todo revisado";
  $("kpi-total").textContent = s.total;
  $("kpi-promedio").textContent = s.publicadas ? s.promedio.toFixed(1) + " ★" : "—";
  $("kpi-reportadas").textContent = s.opiniones_reportadas;
  $("kpi-ocultas").textContent = s.ocultas;

  const elegido = $("filtro-producto").value;
  $("filtro-producto").innerHTML = '<option value="">Todos</option>' +
    r.productos.map((p) => `<option value="${p.id}">${texto(p.nombre)}</option>`).join("");
  $("filtro-producto").value = elegido;

  pintarLista(r.filtro);
}

async function recargar() {
  try {
    await cargarOpiniones();
    ocultarError();
  } catch (e) {
    mostrarError(e);
  }
}

// ---------- Acciones ----------
let opinionOcultar = null;

function abrirOcultar(o) {
  opinionOcultar = o;
  $("form-ocultar").reset();
  $("campo-otro").hidden = true;
  $("oc-error").hidden = true;
  $("oc-texto").innerHTML = `Opinión de <strong>${texto(o.cliente)}</strong> sobre <strong>${texto(o.producto)}</strong>
    (${o.estrellas} estrella${o.estrellas === 1 ? "" : "s"}). Dejará de verse en la app y de contar en el promedio.`;
  // Si la reportaron, se sugiere el motivo del reporte
  const motivo = (o.motivos[0] || {}).motivo || "";
  if (motivo.startsWith("Spam")) $("oc-motivo").value = "Spam o publicidad";
  else if (motivo.startsWith("Falsa")) $("oc-motivo").value = "Información falsa o engañosa";
  $("dlg-ocultar").showModal();
}

async function guardarOcultar(evento) {
  evento.preventDefault();
  $("oc-error").hidden = true;
  const motivo = $("oc-motivo").value === "otro" ? $("oc-otro").value.trim() : $("oc-motivo").value;
  if (motivo.length < 3) {
    $("oc-error").textContent = "Escribe el motivo (mínimo 3 letras).";
    $("oc-error").hidden = false;
    return;
  }
  const boton = $("oc-guardar");
  boton.disabled = true;
  boton.textContent = "Ocultando...";
  try {
    const r = await api(`/admin/opiniones/${opinionOcultar.id}/ocultar`, { metodo: "POST", datos: { motivo } });
    $("dlg-ocultar").close();
    mostrarOk(r.mensaje);
    await recargar();
  } catch (e) {
    $("oc-error").textContent = e.message;
    $("oc-error").hidden = false;
  } finally {
    boton.disabled = false;
    boton.textContent = "Ocultar opinión";
  }
}

async function accionDirecta(boton, ruta) {
  boton.disabled = true;
  try {
    const r = await api(ruta, { metodo: "POST" });
    mostrarOk(r.mensaje);
    await recargar();
  } catch (e) {
    boton.disabled = false;
    mostrarError(e);
  }
}

function alHacerClicEnLista(evento) {
  const verFoto = evento.target.closest("button[data-ver]");
  if (verFoto) {
    urlFoto(verFoto.dataset.ver).then((local) => {
      $("foto-grande").src = local;
      $("dlg-foto").showModal();
    }).catch(() => mostrarError(new Error("No se pudo abrir la foto.")));
    return;
  }

  const boton = evento.target.closest("button[data-accion]");
  if (!boton) return;
  const o = opiniones.find((x) => String(x.id) === boton.dataset.id);
  if (!o) return;
  if (boton.dataset.accion === "ocultar") abrirOcultar(o);
  else if (boton.dataset.accion === "mostrar") accionDirecta(boton, `/admin/opiniones/${o.id}/mostrar`);
  else if (boton.dataset.accion === "revisar") accionDirecta(boton, `/admin/opiniones/${o.id}/revisar`);
}

// ---------- Arranque ----------
(async () => {
  const usuario = await Sesion.proteger(["ADMIN"], "index.html");
  if (!usuario) return;

  $("btn-cerrar-sesion").addEventListener("click", (evento) => {
    evento.preventDefault();
    Sesion.salir();
  });

  const nombre = [usuario.nombre, usuario.apellidos].filter(Boolean).join(" ");
  $("alianza-nombre").textContent = nombre || "Mi alianza";
  $("alianza-iniciales").textContent = iniciales(nombre);

  ["filtro", "filtro-producto", "filtro-estrellas"].forEach((id) => $(id).addEventListener("change", recargar));
  let espera;
  $("buscar").addEventListener("input", () => {
    clearTimeout(espera);
    espera = setTimeout(recargar, 400);
  });

  $("lista-opiniones").addEventListener("click", alHacerClicEnLista);

  $("oc-motivo").addEventListener("change", () => {
    $("campo-otro").hidden = $("oc-motivo").value !== "otro";
    if (!$("campo-otro").hidden) $("oc-otro").focus();
  });
  $("form-ocultar").addEventListener("submit", guardarOcultar);
  $("oc-cancelar").addEventListener("click", () => $("dlg-ocultar").close());

  $("foto-cerrar").addEventListener("click", () => $("dlg-foto").close());
  $("dlg-foto").addEventListener("click", (evento) => {
    if (evento.target === $("dlg-foto")) $("dlg-foto").close();   // clic fuera de la foto
  });

  await recargar();
})();