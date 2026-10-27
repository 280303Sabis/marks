/*
  inventario.js - Inventario y kárdex del panel (PASO W9)
  --------------------------------------------------------
  Lo usa inventario.html.
  1. Protege la página: sin sesión de ADMIN regresa a index.html.
  2. Muestra las existencias de la sucursal con sus alertas.
  3. Registra entradas, mermas y ajustes por conteo (ventana "movimiento").
  4. Cambia el stock mínimo y la caducidad (ventana "editar").
  5. Muestra el kárdex: todas las entradas y salidas con quién las hizo.
  6. Pestañas para ver Existencias o Entradas y salidas (sin scroll largo).

  Rutas de la API que usa:
    GET  /admin/inventario?sucursal_id=
    GET  /admin/kardex?sucursal_id=&producto_id=&tipo=&periodo=
    POST /admin/inventario/movimiento
    PUT  /admin/inventario/<producto_id>
*/

// ---------- Ayudantes ----------
const $ = (id) => document.getElementById(id);

// Piezas sin decimales; kilos con hasta 3 decimales.
function cantidad(n) {
  return Number(n || 0).toLocaleString("es-MX", { maximumFractionDigits: 3 });
}

function unidadCorta(tipoVenta) {
  return tipoVenta === "GRANEL" ? "kg" : "pzas";
}

// Evita que un nombre con < o > se interprete como HTML.
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

function filaVacia(columnas, icono, titulo, detalle) {
  return `<tr><td colspan="${columnas}" class="adm-vacio">
            <i class="ph ph-${icono}" aria-hidden="true"></i>
            <strong>${titulo}</strong>${detalle}</td></tr>`;
}

// "2026-11-06" -> fecha local (sin que la zona horaria la mueva un día)
function soloFecha(iso) {
  return iso ? new Date(String(iso).slice(0, 10) + "T12:00:00") : null;
}

function fechaLarga(iso) {
  const f = soloFecha(iso);
  return f ? f.toLocaleDateString("es-MX", { day: "numeric", month: "short", year: "numeric" }).replace(".", "") : "";
}

// "2026-10-27 14:32" -> "27 oct 2026, 14:32"
function fechaHora(textoFecha) {
  if (!textoFecha) return "";
  const [dia, hora] = textoFecha.split(" ");
  return fechaLarga(dia) + (hora ? ", " + hora : "");
}

function hoyIso() {
  const h = new Date();
  return `${h.getFullYear()}-${String(h.getMonth() + 1).padStart(2, "0")}-${String(h.getDate()).padStart(2, "0")}`;
}

// Días que faltan para una fecha (negativo = ya pasó)
function diasPara(iso) {
  const hoy = soloFecha(hoyIso());
  return Math.round((soloFecha(iso) - hoy) / 86400000);
}

// ---------- Avisos arriba de la página ----------
function mostrarError(e) {
  const aviso = $("aviso-api");
  let mensaje = e.message || "No se pudieron cargar los datos.";
  if (e.estado === 404) {
    mensaje = "La API todavía no tiene el módulo de inventario. Revisa que estés usando la API nueva (PASO W9).";
  }
  aviso.innerHTML = '<i class="ph ph-warning-circle" aria-hidden="true"></i><span>' + texto(mensaje) + "</span>";
  aviso.hidden = false;
  document.querySelectorAll(".adm-cargando").forEach((fila) => fila.remove());
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

// ---------- Sucursal elegida (la misma que usan las otras páginas del panel) ----------
const SUCURSAL_KEY = "marks_admin_sucursal";
let sucursalActual = null;

function sucursalElegida() {
  return sessionStorage.getItem(SUCURSAL_KEY) || "";
}

function pintarSucursal(sucursales, actual) {
  sucursalActual = actual;
  const select = $("sucursal");
  select.innerHTML = sucursales
    .map((s) => `<option value="${s.id}">${texto(s.nombre)}</option>`)
    .join("");
  select.value = String(actual.id);
  $("sucursal-direccion").textContent = [actual.direccion, actual.municipio].filter(Boolean).join(", ");
}

// ---------- Existencias ----------
let productos = [];   // inventario de la sucursal (lo que regresó la API)

function insignias(p) {
  const lista = [];
  if (!p.activo) lista.push(["gris", "eye-slash", "Inactivo"]);
  if (p.caducado) lista.push(["error", "warning-octagon", "Caducado"]);
  if (Number(p.stock) <= 0) lista.push(["error", "package", "Sin existencia"]);
  else if (p.stock_bajo) lista.push(["aviso", "trend-down", "Stock bajo"]);
  if (p.caducidad_proxima) lista.push(["aviso", "clock-countdown", "Caduca pronto"]);
  if (!lista.length) lista.push(["ok", "check-circle", "En orden"]);
  return `<div class="inv-insignias">${lista.map(([clase, icono, nombre]) =>
    `<span class="inv-insignia ${clase}"><i class="ph ph-${icono}" aria-hidden="true"></i>${nombre}</span>`).join("")}</div>`;
}

function celdaCaducidad(p) {
  if (!p.fecha_caducidad) return '<span class="cl-texto-sec">No caduca</span>';
  const dias = diasPara(p.fecha_caducidad);
  let nota = `en ${dias} días`;
  let clase = "";
  if (dias < 0) { nota = `venció hace ${-dias} día${dias === -1 ? "" : "s"}`; clase = "error"; }
  else if (dias === 0) { nota = "vence hoy"; clase = "error"; }
  else if (dias === 1) { nota = "vence mañana"; clase = "aviso"; }
  else if (dias <= 3) { clase = "aviso"; }
  return `<span class="inv-cad">${fechaLarga(p.fecha_caducidad)}</span>
          <span class="inv-cad-dias ${clase}">${nota}</span>`;
}

function filaProducto(p) {
  const u = unidadCorta(p.tipo_venta);
  const claseStock = Number(p.stock) <= 0 ? " cero" : (p.stock_bajo ? " bajo" : "");
  const codigo = p.plu ? "PLU " + p.plu : p.codigo_barras;
  return `<tr class="${p.activo ? "" : "inv-inactivo"}" data-buscar="${texto((p.nombre + " " + p.codigo_barras + " " + (p.plu || "")).toLowerCase())}">
      <td><span class="adm-producto">${texto(p.nombre)}${p.es_local ? '<span class="inv-local" title="' + texto(p.productor || "Productor local") + '">Local NL</span>' : ""}</span>
          <span class="adm-sub">${texto(p.categoria || "Sin categoría")} · ${texto(codigo)}</span></td>
      <td class="num"><span class="inv-existencia${claseStock}">${cantidad(p.stock)}</span> ${u}</td>
      <td class="num">${cantidad(p.stock_minimo)} ${u}</td>
      <td>${celdaCaducidad(p)}</td>
      <td>${insignias(p)}</td>
      <td class="num">
        <div class="inv-acciones">
          <button type="button" class="inv-accion" data-accion="ENTRADA" data-id="${p.producto_id}" title="Registrar entrada" aria-label="Registrar entrada de ${texto(p.nombre)}"><i class="ph ph-plus-circle" aria-hidden="true"></i></button>
          <button type="button" class="inv-accion merma" data-accion="MERMA" data-id="${p.producto_id}" title="Registrar merma" aria-label="Registrar merma de ${texto(p.nombre)}"><i class="ph ph-minus-circle" aria-hidden="true"></i></button>
          <button type="button" class="inv-accion" data-accion="AJUSTE" data-id="${p.producto_id}" title="Ajustar por conteo físico" aria-label="Ajustar por conteo ${texto(p.nombre)}"><i class="ph ph-scales" aria-hidden="true"></i></button>
          <button type="button" class="inv-accion" data-accion="editar" data-id="${p.producto_id}" title="Mínimo y caducidad" aria-label="Mínimo y caducidad de ${texto(p.nombre)}"><i class="ph ph-pencil-simple" aria-hidden="true"></i></button>
          <button type="button" class="inv-accion" data-accion="kardex" data-id="${p.producto_id}" title="Ver su kárdex" aria-label="Ver kárdex de ${texto(p.nombre)}"><i class="ph ph-list-bullets" aria-hidden="true"></i></button>
        </div>
      </td>
    </tr>`;
}

function filtrarTabla() {
  const buscar = $("buscar-producto").value.trim().toLowerCase();
  let visibles = 0;
  document.querySelectorAll("#tabla-inventario tr[data-buscar]").forEach((fila) => {
    const ver = !buscar || fila.dataset.buscar.includes(buscar);
    fila.hidden = !ver;
    if (ver) visibles++;
  });
  const vacio = $("fila-sin-resultados");
  if (vacio) vacio.remove();
  if (productos.length && !visibles) {
    $("tabla-inventario").insertAdjacentHTML("beforeend",
      filaVacia(6, "magnifying-glass", "Sin resultados", "Ningún producto coincide con la búsqueda.")
        .replace("<tr>", '<tr id="fila-sin-resultados">'));
  }
}

async function cargarInventario() {
  const r = await api("/admin/inventario?sucursal_id=" + sucursalElegida());
  pintarSucursal(r.sucursales, r.sucursal);
  productos = r.productos;

  $("inv-total").textContent = r.resumen.productos;
  const inactivos = productos.length - r.resumen.productos;
  $("inv-total-nota").textContent = r.resumen.productos
    ? `Activos en esta sucursal${inactivos ? ` · ${inactivos} inactivo(s)` : ""}`
    : "Esta sucursal no tiene productos";
  $("kpi-sin-stock").textContent = r.resumen.sin_stock;
  $("kpi-stock-bajo").textContent = r.resumen.stock_bajo;
  $("kpi-caducar").textContent = r.resumen.por_caducar;
  $("kpi-caducados").textContent = r.resumen.caducados;

  $("tabla-inventario").innerHTML = productos.length
    ? productos.map(filaProducto).join("")
    : filaVacia(6, "package", "Sin productos", "Esta sucursal todavía no tiene inventario.");
  filtrarTabla();

  // Lista de productos del filtro del kárdex (se conserva lo elegido)
  const elegido = $("k-producto").value;
  $("k-producto").innerHTML = '<option value="">Todos los productos</option>' +
    productos.map((p) => `<option value="${p.producto_id}">${texto(p.nombre)}</option>`).join("");
  if (productos.some((p) => String(p.producto_id) === elegido)) $("k-producto").value = elegido;
}

// ---------- Kárdex ----------
const MOVIMIENTOS = {
  ENTRADA: ["entrada", "arrow-circle-down", "Entrada"],
  SALIDA_VENTA: ["venta", "shopping-cart-simple", "Venta"],
  MERMA: ["merma", "trash", "Merma"],
  AJUSTE: ["ajuste", "scales", "Ajuste"],
};

async function cargarKardex() {
  const filtros = new URLSearchParams({
    sucursal_id: sucursalElegida(),
    periodo: $("k-periodo").value,
    tipo: $("k-tipo").value,
  });
  if ($("k-producto").value) filtros.set("producto_id", $("k-producto").value);
  const r = await api("/admin/kardex?" + filtros);

  // Con un solo producto los totales van en su unidad (pzas o kg)
  const uno = productos.find((p) => String(p.producto_id) === $("k-producto").value);
  const u = uno ? " " + unidadCorta(uno.tipo_venta) : "";
  const conSigno = (n) => (Number(n) > 0 ? "+" : "") + cantidad(n);
  $("k-entradas").textContent = cantidad(r.totales.entradas) + u;
  $("k-ventas").textContent = cantidad(r.totales.ventas) + u;
  $("k-mermas").textContent = cantidad(r.totales.mermas) + u;
  $("k-ajustes").textContent = conSigno(r.totales.ajustes) + u;
  $("k-nota-totales").textContent = uno
    ? `Totales de ${uno.nombre} en el periodo.`
    : "Los totales suman piezas y kilos; filtra un producto para verlos en su unidad.";

  $("tabla-kardex").innerHTML = r.movimientos.length
    ? r.movimientos.map((m) => {
        const [clase, icono, nombre] = MOVIMIENTOS[m.tipo] || ["", "circle", m.tipo];
        const unidad = unidadCorta(m.tipo_venta);
        const n = Number(m.cantidad);
        const detalle = m.folio
          ? `<span class="adm-folio">${texto(m.folio)}</span>`
          : texto(m.nota || "");
        return `<tr>
          <td>${texto(fechaHora(m.fecha))}</td>
          <td><span class="adm-producto">${texto(m.producto)}</span></td>
          <td><span class="inv-mov ${clase}"><i class="ph ph-${icono}" aria-hidden="true"></i>${nombre}</span></td>
          <td class="num"><span class="inv-cantidad ${n >= 0 ? "positivo" : "negativo"}">${n > 0 ? "+" : ""}${cantidad(n)} ${unidad}</span></td>
          <td class="num">${cantidad(m.stock_final)} ${unidad}</td>
          <td>${texto(m.usuario)}</td>
          <td class="inv-detalle">${detalle}</td>
        </tr>`;
      }).join("")
    : filaVacia(7, "list-bullets", "Sin movimientos", "No hay entradas ni salidas con estos filtros.");
}

// ---------- Ventana: entrada, merma o ajuste ----------
const TEXTOS_MOVIMIENTO = {
  ENTRADA: { titulo: "Registrar entrada", cantidad: "Cantidad que llegó", nota: "Nota", notaObligatoria: false,
             placeholder: "Ej. pedido del proveedor", boton: "Registrar entrada" },
  MERMA: { titulo: "Registrar merma", cantidad: "Cantidad a dar de baja", nota: "Motivo", notaObligatoria: true,
           placeholder: "Ej. empaque roto, producto caducado", boton: "Registrar merma" },
  AJUSTE: { titulo: "Ajustar por conteo físico", cantidad: "Existencia real contada", nota: "Motivo", notaObligatoria: true,
            placeholder: "Ej. conteo físico del pasillo", boton: "Guardar ajuste" },
};

let productoMov = null;

function abrirMovimiento(producto, tipo) {
  productoMov = producto;
  $("form-movimiento").reset();
  $("mov-tipo").value = tipo;
  $("mov-caducidad").min = hoyIso();
  ocultarErrorMov();
  ajustarFormularioMov();
  $("dlg-movimiento").showModal();
  $("mov-cantidad").focus();
}

function ajustarFormularioMov() {
  const tipo = $("mov-tipo").value;
  const t = TEXTOS_MOVIMIENTO[tipo];
  const p = productoMov;
  const granel = p.tipo_venta === "GRANEL";

  $("mov-titulo").textContent = t.titulo;
  $("mov-producto").innerHTML = `<strong>${texto(p.nombre)}</strong> · existencia actual: ${cantidad(p.stock)} ${unidadCorta(p.tipo_venta)}`;
  $("mov-cantidad-label").textContent = t.cantidad;
  $("mov-unidad").textContent = unidadCorta(p.tipo_venta);
  $("mov-cantidad").step = granel ? "0.001" : "1";
  $("mov-cantidad").placeholder = granel ? "Ej. 2.500" : "Ej. 12";
  $("mov-nota-label").innerHTML = t.notaObligatoria ? t.nota : `${t.nota} <span class="cl-opcional">(opcional)</span>`;
  $("mov-nota").placeholder = t.placeholder;
  $("mov-nota").required = t.notaObligatoria;
  $("campo-caducidad").hidden = tipo !== "ENTRADA";
  $("mov-guardar").textContent = t.boton;
  actualizarResumenMov();
}

// "Existencia: 60 -> 72 pzas"
function actualizarResumenMov() {
  const resumen = $("mov-resumen");
  const valor = $("mov-cantidad").value.trim();
  const p = productoMov;
  if (!valor || isNaN(Number(valor))) {
    resumen.textContent = "";
    return;
  }
  const n = Number(valor);
  const actual = Number(p.stock);
  const tipo = $("mov-tipo").value;
  const final = tipo === "ENTRADA" ? actual + n : tipo === "MERMA" ? actual - n : n;
  const u = unidadCorta(p.tipo_venta);
  resumen.className = "inv-resumen" + (final < 0 ? " error" : "");
  if (tipo === "AJUSTE") {
    const diferencia = n - actual;
    resumen.innerHTML = `Existencia: ${cantidad(actual)} → <strong>${cantidad(final)} ${u}</strong>` +
      (diferencia ? ` (${diferencia > 0 ? "sobran" : "faltan"} ${cantidad(Math.abs(diferencia))} ${u})` : " (sin diferencia)");
  } else {
    resumen.innerHTML = `Existencia: ${cantidad(actual)} → <strong>${cantidad(final)} ${u}</strong>`;
  }
}

function mostrarErrorMov(mensaje) {
  $("mov-error").textContent = mensaje;
  $("mov-error").hidden = false;
}

function ocultarErrorMov() {
  $("mov-error").hidden = true;
}

// Revisa la cantidad antes de mandarla (la API vuelve a revisar todo).
function problemaCantidad(valor, tipoVenta, permiteCero) {
  if (valor === "" || isNaN(Number(valor))) return "Escribe una cantidad.";
  const n = Number(valor);
  if (n < 0) return "La cantidad no puede ser negativa.";
  if (n === 0 && !permiteCero) return "La cantidad debe ser mayor que cero.";
  if (n > 9999) return "La cantidad máxima por movimiento es 9999.";
  if (tipoVenta !== "GRANEL" && !Number.isInteger(n)) return "Este producto se vende por pieza: usa números enteros.";
  if (tipoVenta === "GRANEL" && Math.abs(n * 1000 - Math.round(n * 1000)) > 1e-6) {
    return "Usa máximo 3 decimales (gramos).";
  }
  return null;
}

async function guardarMovimiento(evento) {
  evento.preventDefault();
  ocultarErrorMov();
  const p = productoMov;
  const tipo = $("mov-tipo").value;
  const valor = $("mov-cantidad").value.trim();
  const nota = $("mov-nota").value.trim();

  const problema = problemaCantidad(valor, p.tipo_venta, tipo === "AJUSTE");
  if (problema) return mostrarErrorMov(problema);
  if (tipo === "MERMA" && Number(valor) > Number(p.stock)) {
    return mostrarErrorMov(`Solo hay ${cantidad(p.stock)} ${unidadCorta(p.tipo_venta)} en existencia.`);
  }
  if (tipo === "AJUSTE" && Number(valor) === Number(p.stock)) {
    return mostrarErrorMov("El conteo es igual a la existencia actual; no hay nada que ajustar.");
  }
  if (TEXTOS_MOVIMIENTO[tipo].notaObligatoria && nota.length < 3) {
    return mostrarErrorMov("Escribe el motivo (por ejemplo: empaque roto, conteo físico).");
  }
  if (tipo === "ENTRADA" && $("mov-caducidad").value && $("mov-caducidad").value < hoyIso()) {
    return mostrarErrorMov("La caducidad ya pasó; registra el producto como merma.");
  }

  const datos = { tipo, sucursal_id: sucursalActual.id, producto_id: p.producto_id, nota };
  if (tipo === "AJUSTE") datos.stock_real = valor;
  else datos.cantidad = valor;
  if (tipo === "ENTRADA" && $("mov-caducidad").value) datos.fecha_caducidad = $("mov-caducidad").value;

  const boton = $("mov-guardar");
  const textoBoton = boton.textContent;
  boton.disabled = true;
  boton.textContent = "Guardando...";
  try {
    const r = await api("/admin/inventario/movimiento", { metodo: "POST", datos });
    $("dlg-movimiento").close();
    mostrarOk(r.mensaje);
    await recargarTodo();
  } catch (e) {
    mostrarErrorMov(e.message);
  } finally {
    boton.disabled = false;
    boton.textContent = textoBoton;
  }
}

// ---------- Ventana: stock mínimo y caducidad ----------
let productoEd = null;

function abrirEditar(producto) {
  productoEd = producto;
  $("ed-error").hidden = true;
  $("ed-producto").innerHTML = `<strong>${texto(producto.nombre)}</strong> · existencia actual: ${cantidad(producto.stock)} ${unidadCorta(producto.tipo_venta)}`;
  $("ed-unidad").textContent = unidadCorta(producto.tipo_venta);
  $("ed-minimo").step = producto.tipo_venta === "GRANEL" ? "0.001" : "1";
  $("ed-minimo").value = Number(producto.stock_minimo);
  $("ed-caducidad").value = producto.fecha_caducidad ? String(producto.fecha_caducidad).slice(0, 10) : "";
  $("dlg-editar").showModal();
  $("ed-minimo").focus();
}

async function guardarEditar(evento) {
  evento.preventDefault();
  $("ed-error").hidden = true;
  const valor = $("ed-minimo").value.trim();
  const problema = problemaCantidad(valor, productoEd.tipo_venta, true);
  if (problema) {
    $("ed-error").textContent = problema.replace("La cantidad", "El stock mínimo");
    $("ed-error").hidden = false;
    return;
  }

  const boton = $("ed-guardar");
  boton.disabled = true;
  boton.textContent = "Guardando...";
  try {
    const r = await api("/admin/inventario/" + productoEd.producto_id, {
      metodo: "PUT",
      datos: { sucursal_id: sucursalActual.id, stock_minimo: valor, fecha_caducidad: $("ed-caducidad").value },
    });
    $("dlg-editar").close();
    mostrarOk(r.mensaje + ": " + productoEd.nombre);
    await recargarTodo();
  } catch (e) {
    $("ed-error").textContent = e.message;
    $("ed-error").hidden = false;
  } finally {
    boton.disabled = false;
    boton.textContent = "Guardar";
  }
}

// ---------- Pestañas: Existencias | Entradas y salidas ----------
const PESTANA_KEY = "marks_admin_inv_pestana";

function mostrarPestana(nombre) {
  const kardex = nombre === "kardex";
  $("seccion-existencias").hidden = kardex;
  $("seccion-kardex").hidden = !kardex;
  $("tab-existencias").classList.toggle("activa", !kardex);
  $("tab-kardex").classList.toggle("activa", kardex);
  $("tab-existencias").setAttribute("aria-selected", String(!kardex));
  $("tab-kardex").setAttribute("aria-selected", String(kardex));
  sessionStorage.setItem(PESTANA_KEY, kardex ? "kardex" : "existencias");
}

// ---------- Acciones de la tabla ----------
function alHacerClicEnTabla(evento) {
  const boton = evento.target.closest("button[data-accion]");
  if (!boton) return;
  const producto = productos.find((p) => String(p.producto_id) === boton.dataset.id);
  if (!producto) return;

  const accion = boton.dataset.accion;
  if (accion === "editar") {
    abrirEditar(producto);
  } else if (accion === "kardex") {
    $("k-producto").value = String(producto.producto_id);
    cargarKardex().then(ocultarError).catch(mostrarError);
    mostrarPestana("kardex");
    $("pestanas").scrollIntoView({ behavior: "smooth", block: "start" });
  } else {
    abrirMovimiento(producto, accion);
  }
}

// ---------- Carga ----------
async function recargarTodo() {
  try {
    await cargarInventario();
    await cargarKardex();
    ocultarError();
  } catch (e) {
    mostrarError(e);
  }
}

// ---------- Arranque ----------
(async () => {
  const usuario = await Sesion.proteger(["ADMIN"], "index.html");
  if (!usuario) return;   // ya se está regresando al acceso

  $("btn-cerrar-sesion").addEventListener("click", (evento) => {
    evento.preventDefault();
    Sesion.salir();
  });

  const nombre = [usuario.nombre, usuario.apellidos].filter(Boolean).join(" ");
  $("alianza-nombre").textContent = nombre || "Mi alianza";
  $("alianza-iniciales").textContent = iniciales(nombre);

  $("sucursal").addEventListener("change", () => {
    sessionStorage.setItem(SUCURSAL_KEY, $("sucursal").value);
    $("k-producto").value = "";
    recargarTodo();
  });

  // Pestañas (se recuerda la última mientras la pestaña del navegador siga abierta)
  $("tab-existencias").addEventListener("click", () => mostrarPestana("existencias"));
  $("tab-kardex").addEventListener("click", () => mostrarPestana("kardex"));
  mostrarPestana(sessionStorage.getItem(PESTANA_KEY) || "existencias");

  $("buscar-producto").addEventListener("input", filtrarTabla);
  $("tabla-inventario").addEventListener("click", alHacerClicEnTabla);
  ["k-producto", "k-tipo", "k-periodo"].forEach((id) =>
    $(id).addEventListener("change", () => cargarKardex().then(ocultarError).catch(mostrarError)));

  // Ventana de movimiento
  $("mov-tipo").addEventListener("change", ajustarFormularioMov);
  $("mov-cantidad").addEventListener("input", actualizarResumenMov);
  $("form-movimiento").addEventListener("submit", guardarMovimiento);
  $("mov-cancelar").addEventListener("click", () => $("dlg-movimiento").close());

  // Ventana de mínimo y caducidad
  $("form-editar").addEventListener("submit", guardarEditar);
  $("ed-cancelar").addEventListener("click", () => $("dlg-editar").close());

  await recargarTodo();
})();