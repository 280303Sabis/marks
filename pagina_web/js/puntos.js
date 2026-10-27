/*
  puntos.js - Puntos de los clientes en el panel (PASO W13)
  ----------------------------------------------------------
  Lo usa puntos.html.
  1. Protege la página: sin sesión de ADMIN regresa a index.html.
  2. Lista los clientes con su saldo de puntos (buscar y ordenar).
  3. "Ajustar" abre la ventana del cliente: su estado de cuenta y el
     formulario para sumar o quitar puntos con un motivo.
     El cliente ve el ajuste y el motivo en "Mis puntos" de la app.

  Rutas de la API que usa:
    GET  /admin/clientes?buscar=&orden=
    GET  /admin/clientes/<id>/puntos
    POST /admin/clientes/<id>/puntos   {puntos, motivo}
*/

// ---------- Ayudantes ----------
const $ = (id) => document.getElementById(id);
const MAX_AJUSTE = 5000;

function texto(t) {
  const d = document.createElement("div");
  d.textContent = t == null ? "" : String(t);
  return d.innerHTML;
}

function numero(n) {
  return Number(n || 0).toLocaleString("es-MX");
}

// 100 puntos = $10 (solo bloques completos)
function pesos(puntos) {
  return "$" + numero(Math.floor(Number(puntos || 0) / 100) * 10);
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

// ---------- Avisos ----------
function mostrarError(e) {
  const aviso = $("aviso-api");
  let mensaje = e.message || "No se pudieron cargar los datos.";
  if (e.estado === 404) {
    mensaje = "La API todavía no tiene el módulo de puntos. Revisa que estés usando la API nueva (PASO W13).";
  }
  aviso.innerHTML = '<i class="ph ph-warning-circle" aria-hidden="true"></i><span>' + texto(mensaje) + "</span>";
  aviso.hidden = false;
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

// ---------- Lista de clientes ----------
let clientes = [];

function filaCliente(c) {
  return `<tr>
      <td>
        <span class="adm-producto">${texto(c.nombre)}</span>${c.activo ? "" : '<span class="pts-inactivo">Desactivada</span>'}
        <span class="adm-sub">${texto(c.correo)}</span>
      </td>
      <td class="num">${numero(c.compras)}</td>
      <td class="pts-col-fecha">${c.ultima_compra ? texto(fechaHora(c.ultima_compra)) : '<span class="adm-sub">Sin compras</span>'}</td>
      <td class="num"><span class="pts-puntos${c.puntos ? "" : " cero"}">${numero(c.puntos)}</span></td>
      <td class="num pts-col-pesos">${pesos(c.puntos)}</td>
      <td class="num">
        <button type="button" class="cl-boton-sec pts-boton-ajustar" data-id="${c.id}">
          <i class="ph ph-sliders-horizontal" aria-hidden="true"></i>Ajustar
        </button>
      </td>
    </tr>`;
}

async function cargarClientes() {
  const filtros = new URLSearchParams({ orden: $("orden").value });
  if ($("buscar").value.trim()) filtros.set("buscar", $("buscar").value.trim());
  const r = await api("/admin/clientes?" + filtros);
  clientes = r.clientes;

  const s = r.resumen;
  $("pts-circulacion").textContent = numero(s.puntos_en_circulacion);
  $("pts-circulacion-nota").textContent = `Equivalen a ${pesos(s.puntos_en_circulacion)} en descuentos`;
  $("kpi-clientes").textContent = numero(s.clientes);
  $("kpi-con-puntos").textContent = numero(s.con_puntos);
  $("kpi-ajustes").textContent = numero(s.ajustes_30_dias);
  $("kpi-neto").textContent = (s.ajustes_neto_30_dias > 0 ? "+" : "") + numero(s.ajustes_neto_30_dias);

  const buscando = $("buscar").value.trim();
  $("titulo-lista").textContent = buscando ? `Resultados para "${buscando}"` : "Clientes";
  $("tabla-clientes").innerHTML = clientes.length
    ? clientes.map(filaCliente).join("")
    : `<tr><td colspan="6" class="adm-vacio">${buscando ? "Ningún cliente coincide con la búsqueda." : "Todavía no hay clientes registrados."}</td></tr>`;
}

async function recargar() {
  try {
    await cargarClientes();
    ocultarError();
  } catch (e) {
    mostrarError(e);
    $("tabla-clientes").innerHTML = '<tr><td colspan="6" class="adm-vacio">No se pudo cargar la lista.</td></tr>';
  }
}

// ---------- Ventana del cliente ----------
let clienteAbierto = null;   // {id, nombre, puntos, activo...}

function itemMovimiento(m) {
  const mas = m.puntos > 0;
  const etiqueta = m.tipo === "AJUSTE" ? '<span class="pts-etiqueta-ajuste">Ajuste</span>' : "";
  const detalle = m.folio && m.tipo !== "AJUSTE" ? ` · ${texto(m.folio)}` : "";
  return `<li>
      <span class="pts-mov-nota">${etiqueta}${texto(m.nota || m.tipo_texto)}</span>
      <span class="pts-mov-meta">${texto(m.tipo_texto)} · ${texto(fechaHora(m.fecha))}${detalle}</span>
      <span class="pts-mov-puntos ${mas ? "mas" : "menos"}">${mas ? "+" : "−"}${numero(Math.abs(m.puntos))}
        <small>Saldo ${numero(m.saldo_final)}</small></span>
    </li>`;
}

function pintarCliente(c, movimientos) {
  clienteAbierto = c;
  $("cl-nombre").textContent = c.nombre;
  $("cl-correo").textContent = c.correo + (c.activo ? "" : " · cuenta desactivada");
  $("cl-saldo").textContent = numero(c.puntos);
  $("cl-saldo-pesos").textContent = `Equivalen a ${pesos(c.puntos)}`;
  $("lista-movimientos").innerHTML = movimientos.length
    ? movimientos.map(itemMovimiento).join("")
    : '<li class="pts-vacio">Todavía no tiene movimientos de puntos.</li>';
  $("form-ajuste").hidden = !c.activo;
  actualizarVista();
}

async function abrirCliente(id) {
  const c = clientes.find((x) => String(x.id) === String(id));
  $("form-ajuste").reset();
  $("campo-otro").hidden = true;
  $("aj-error").hidden = true;
  $("lista-movimientos").innerHTML = '<li class="pts-vacio">Cargando…</li>';
  if (c) pintarCliente(c, []);
  $("dlg-cliente").showModal();
  $("aj-puntos").focus();
  try {
    const r = await api(`/admin/clientes/${id}/puntos`);
    pintarCliente(r.cliente, r.movimientos);
  } catch (e) {
    $("lista-movimientos").innerHTML = `<li class="pts-vacio">${texto(e.message)}</li>`;
  }
}

function tipoElegido() {
  return document.querySelector('input[name="tipo"]:checked').value;
}

// Puntos con signo según "Sumar" o "Quitar" (null si la cantidad no es válida)
function puntosConSigno() {
  const valor = $("aj-puntos").value.trim();
  if (!/^\d+$/.test(valor)) return null;
  const n = Number(valor);
  if (n < 1 || n > MAX_AJUSTE) return null;
  return tipoElegido() === "restar" ? -n : n;
}

function actualizarVista() {
  const vista = $("aj-vista");
  const boton = $("aj-guardar");
  const restar = tipoElegido() === "restar";
  boton.classList.toggle("restar", restar);
  boton.textContent = restar ? "Quitar puntos" : "Sumar puntos";

  if (!clienteAbierto) return;
  const p = puntosConSigno();
  if (p === null) {
    vista.className = "pts-vista";
    vista.textContent = "";
    return;
  }
  const nuevo = clienteAbierto.puntos + p;
  if (nuevo < 0) {
    vista.className = "pts-vista mal";
    vista.textContent = `Solo tiene ${numero(clienteAbierto.puntos)} puntos; no se le pueden quitar ${numero(-p)}.`;
    return;
  }
  vista.className = "pts-vista";
  vista.innerHTML = `Saldo: ${numero(clienteAbierto.puntos)} → <strong>${numero(nuevo)} puntos</strong> (${pesos(nuevo)})`;
}

function motivoElegido() {
  return $("aj-motivo").value === "otro" ? $("aj-otro").value.trim() : $("aj-motivo").value;
}

async function guardarAjuste(evento) {
  evento.preventDefault();
  const error = $("aj-error");
  error.hidden = true;

  const puntos = puntosConSigno();
  const motivo = motivoElegido();
  let problema = "";
  if (puntos === null) problema = `Escribe una cantidad de 1 a ${numero(MAX_AJUSTE)} puntos (sin decimales).`;
  else if (clienteAbierto.puntos + puntos < 0) problema = `El cliente solo tiene ${numero(clienteAbierto.puntos)} puntos.`;
  else if (motivo.length < 5) problema = "Escribe el motivo (mínimo 5 letras). El cliente lo verá en su app.";
  if (problema) {
    error.textContent = problema;
    error.hidden = false;
    return;
  }

  const boton = $("aj-guardar");
  const textoBoton = boton.textContent;
  boton.disabled = true;
  boton.textContent = "Guardando...";
  try {
    const r = await api(`/admin/clientes/${clienteAbierto.id}/puntos`, {
      metodo: "POST",
      datos: { puntos, motivo },
    });
    $("dlg-cliente").close();
    mostrarOk(r.mensaje);
    await recargar();
  } catch (e) {
    error.textContent = e.message;
    error.hidden = false;
  } finally {
    boton.disabled = false;
    boton.textContent = textoBoton;
  }
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

  $("orden").addEventListener("change", recargar);
  let espera;
  $("buscar").addEventListener("input", () => {
    clearTimeout(espera);
    espera = setTimeout(recargar, 400);
  });

  $("tabla-clientes").addEventListener("click", (evento) => {
    const boton = evento.target.closest("button[data-id]");
    if (boton) abrirCliente(boton.dataset.id);
  });

  document.querySelectorAll('input[name="tipo"]').forEach((r) => r.addEventListener("change", actualizarVista));
  $("aj-puntos").addEventListener("input", actualizarVista);
  $("aj-motivo").addEventListener("change", () => {
    $("campo-otro").hidden = $("aj-motivo").value !== "otro";
    if (!$("campo-otro").hidden) $("aj-otro").focus();
  });
  $("form-ajuste").addEventListener("submit", guardarAjuste);
  $("cl-cerrar").addEventListener("click", () => $("dlg-cliente").close());
  $("dlg-cliente").addEventListener("close", () => { clienteAbierto = null; });

  await recargar();
})();