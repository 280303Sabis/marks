/*
  productos.js - Productos del panel (PASO W10)
  ----------------------------------------------
  Lo usa productos.html.
  1. Protege la página: sin sesión de ADMIN regresa a index.html.
  2. Muestra el catálogo con precio, oferta, calificación y existencia.
  3. Ventana "Editar": nombre, descripción, categoría, precio, oferta
     y productor local de NL.
  4. Interruptores que se guardan al momento: opiniones activas y a la venta
     (desactivar pide confirmación).

  Rutas de la API que usa:
    GET /admin/productos
    PUT /admin/productos/<id>
*/

// ---------- Ayudantes ----------
const $ = (id) => document.getElementById(id);

function dinero(n) {
  return "$" + Number(n || 0).toLocaleString("es-MX", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function cantidad(n) {
  return Number(n || 0).toLocaleString("es-MX", { maximumFractionDigits: 3 });
}

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

// ---------- Avisos ----------
function mostrarError(e) {
  const aviso = $("aviso-api");
  let mensaje = e.message || "No se pudieron cargar los datos.";
  if (e.estado === 404) {
    mensaje = "La API todavía no tiene el módulo de productos. Revisa que estés usando la API nueva (PASO W10).";
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

// ---------- Datos ----------
let productos = [];
let categorias = [];
let productores = [];

function porcentaje(precio, oferta) {
  return Math.round((1 - Number(oferta) / Number(precio)) * 100);
}

function celdaPrecio(p) {
  const kg = p.tipo_venta === "GRANEL" ? " / kg" : "";
  if (p.precio_oferta == null) {
    return `<span class="prd-precio">${dinero(p.precio)}${kg}</span>`;
  }
  return `<span class="prd-precio-antes">${dinero(p.precio)}</span>
          <span class="prd-precio">${dinero(p.precio_oferta)}${kg}</span>
          <span class="prd-descuento">-${porcentaje(p.precio, p.precio_oferta)}%</span>`;
}

function celdaCalificacion(p) {
  const estrellas = p.opiniones
    ? `<span class="prd-estrellas"><i class="ph-fill ph-star" aria-hidden="true"></i>${Number(p.promedio).toFixed(1)}
         <small>(${p.opiniones} opinión${p.opiniones === 1 ? "" : "es"})</small></span>`
    : '<span class="cl-texto-sec">Sin opiniones</span>';
  const reportes = p.reportes_pendientes
    ? `<br><span class="prd-reportes"><i class="ph ph-flag" aria-hidden="true"></i>${p.reportes_pendientes} reporte${p.reportes_pendientes === 1 ? "" : "s"}</span>`
    : "";
  return estrellas + reportes;
}

function interruptor(p, campo, etiqueta) {
  return `<label class="prd-switch" title="${etiqueta}">
            <input type="checkbox" data-campo="${campo}" data-id="${p.id}" ${p[campo] ? "checked" : ""}
                   aria-label="${etiqueta}: ${texto(p.nombre)}">
            <span></span>
          </label>`;
}

function filaProducto(p) {
  const codigo = p.plu ? "PLU " + p.plu : p.codigo_barras;
  const local = p.productor
    ? `<span class="prd-local">Local NL</span>`
    : "";
  return `<tr class="${p.activo ? "" : "prd-inactivo"}">
      <td class="prd-producto"><span class="adm-producto">${texto(p.nombre)}${local}</span>
          <span class="adm-sub">${texto(p.categoria || "Sin categoría")} · ${texto(codigo)}</span>
          ${p.productor ? `<span class="prd-productor">${texto(p.productor)}${p.productor_municipio ? ", " + texto(p.productor_municipio) : ""}</span>` : ""}</td>
      <td class="num">${celdaPrecio(p)}</td>
      <td>${celdaCalificacion(p)}</td>
      <td class="num">${cantidad(p.stock_total)} ${p.tipo_venta === "GRANEL" ? "kg" : "pzas"}
          <span class="adm-sub">${p.sucursales} sucursal${p.sucursales === 1 ? "" : "es"}</span></td>
      <td class="centro prd-fijo">${interruptor(p, "opiniones_activas", "Opiniones activas")}</td>
      <td class="centro prd-fijo">${interruptor(p, "activo", "A la venta")}</td>
      <td class="num prd-fijo"><button type="button" class="prd-editar" data-editar="${p.id}" title="Editar" aria-label="Editar ${texto(p.nombre)}"><i class="ph ph-pencil-simple" aria-hidden="true"></i></button></td>
    </tr>`;
}

function pintarTabla() {
  const buscar = $("buscar").value.trim().toLowerCase();
  const categoria = $("filtro-categoria").value;
  const estado = $("filtro-estado").value;

  const lista = productos.filter((p) => {
    const textoBuscar = (p.nombre + " " + p.codigo_barras + " " + (p.plu || "")).toLowerCase();
    if (buscar && !textoBuscar.includes(buscar)) return false;
    if (categoria && String(p.categoria_id) !== categoria) return false;
    if (estado === "activos" && !p.activo) return false;
    if (estado === "inactivos" && p.activo) return false;
    if (estado === "oferta" && p.precio_oferta == null) return false;
    if (estado === "locales" && !p.productor_id) return false;
    if (estado === "reportes" && !p.reportes_pendientes) return false;
    return true;
  });

  $("tabla-productos-admin").innerHTML = lista.length
    ? lista.map(filaProducto).join("")
    : filaVacia(7, "magnifying-glass", "Sin resultados", "Ningún producto coincide con los filtros.");
}

async function cargarProductos() {
  const r = await api("/admin/productos");
  productos = r.productos;
  categorias = r.categorias;
  productores = r.productores;

  $("prd-activos").textContent = r.resumen.activos;
  const inactivos = r.resumen.productos - r.resumen.activos;
  $("prd-activos-nota").textContent = `De ${r.resumen.productos} en el catálogo` +
    (inactivos ? ` · ${inactivos} desactivado${inactivos === 1 ? "" : "s"}` : "");
  $("kpi-oferta").textContent = r.resumen.en_oferta;
  $("kpi-locales").textContent = r.resumen.locales;
  $("kpi-sin-opiniones").textContent = r.resumen.opiniones_apagadas;
  $("kpi-reportes").textContent = productos.reduce((s, p) => s + Number(p.reportes_pendientes || 0), 0);

  const elegida = $("filtro-categoria").value;
  $("filtro-categoria").innerHTML = '<option value="">Todas</option>' +
    categorias.map((c) => `<option value="${c.id}">${texto(c.nombre)}</option>`).join("");
  $("filtro-categoria").value = elegida;

  pintarTabla();
}

async function recargar() {
  try {
    await cargarProductos();
    ocultarError();
  } catch (e) {
    mostrarError(e);
  }
}

// ---------- Interruptores ----------
let pendienteDesactivar = null;   // {casilla, producto} mientras se confirma

async function guardarInterruptor(casilla, producto) {
  const campo = casilla.dataset.campo;
  casilla.disabled = true;
  try {
    const r = await api("/admin/productos/" + producto.id, {
      metodo: "PUT",
      datos: { [campo]: casilla.checked },
    });
    const nombres = {
      opiniones_activas: casilla.checked ? "Opiniones activadas" : "Opiniones apagadas",
      activo: casilla.checked ? "Producto a la venta" : "Producto desactivado",
    };
    mostrarOk(`${nombres[campo]}: ${r.producto.nombre}`);
    await recargar();
  } catch (e) {
    casilla.checked = !casilla.checked;   // regresar como estaba
    casilla.disabled = false;
    mostrarError(e);
  }
}

function alCambiarInterruptor(evento) {
  const casilla = evento.target.closest("input[data-campo]");
  if (!casilla) return;
  const producto = productos.find((p) => String(p.id) === casilla.dataset.id);
  if (!producto) return;

  // Desactivar un producto pide confirmación
  if (casilla.dataset.campo === "activo" && !casilla.checked) {
    pendienteDesactivar = { casilla, producto };
    $("conf-texto").innerHTML = `<strong>${texto(producto.nombre)}</strong> dejará de aparecer en la app:
      los clientes ya no podrán escanearlo ni comprarlo. Puedes volver a activarlo cuando quieras.`;
    $("dlg-confirmar").showModal();
    return;
  }
  guardarInterruptor(casilla, producto);
}

function cerrarConfirmacion(aceptar) {
  const pendiente = pendienteDesactivar;
  pendienteDesactivar = null;
  $("dlg-confirmar").close();
  if (!pendiente) return;
  if (aceptar) guardarInterruptor(pendiente.casilla, pendiente.producto);
  else pendiente.casilla.checked = true;
}

// ---------- Ventana: editar producto ----------
let productoEd = null;

function abrirEditar(producto) {
  productoEd = producto;
  $("ed-error").hidden = true;
  $("ed-titulo").textContent = "Editar producto";
  $("ed-codigo").textContent = (producto.plu ? "PLU " + producto.plu + " · " : "") +
    "Código " + producto.codigo_barras + " · se vende " + (producto.tipo_venta === "GRANEL" ? "por kilo" : "por pieza");
  $("ed-nombre").value = producto.nombre;
  $("ed-descripcion").value = producto.descripcion || "";
  $("ed-categoria").innerHTML = '<option value="">Sin categoría</option>' +
    categorias.map((c) => `<option value="${c.id}">${texto(c.nombre)}</option>`).join("");
  $("ed-categoria").value = producto.categoria_id ? String(producto.categoria_id) : "";
  $("ed-precio-label").textContent = producto.tipo_venta === "GRANEL" ? "Precio normal por kg" : "Precio normal";
  $("ed-precio").value = Number(producto.precio).toFixed(2);
  $("ed-oferta").value = producto.precio_oferta == null ? "" : Number(producto.precio_oferta).toFixed(2);
  $("ed-productor").innerHTML = '<option value="">No es producto local</option>' +
    productores.map((pr) => `<option value="${pr.id}">${texto(pr.nombre)}${pr.municipio ? " (" + texto(pr.municipio) + ")" : ""}</option>`).join("");
  $("ed-productor").value = producto.productor_id ? String(producto.productor_id) : "";
  actualizarResumenPrecio();
  $("dlg-producto").showModal();
  $("ed-precio").focus();
}

// "Con oferta el cliente paga $39.00 (25% menos)"
function actualizarResumenPrecio() {
  const resumen = $("ed-resumen-precio");
  const precio = Number($("ed-precio").value);
  const ofertaTexto = $("ed-oferta").value.trim();
  resumen.className = "prd-resumen";
  if (!ofertaTexto) {
    resumen.textContent = precio > 0 ? `Sin oferta: el cliente paga ${dinero(precio)}.` : "";
    return;
  }
  const oferta = Number(ofertaTexto);
  if (!(precio > 0) || !(oferta > 0)) {
    resumen.textContent = "";
  } else if (oferta >= precio) {
    resumen.className = "prd-resumen error";
    resumen.textContent = "La oferta debe ser menor que el precio normal.";
  } else {
    resumen.textContent = `Con oferta el cliente paga ${dinero(oferta)} (${porcentaje(precio, oferta)}% menos).`;
  }
}

function dosDecimales(valor) {
  return /^\d+(\.\d{1,2})?$/.test(valor);
}

async function guardarProducto(evento) {
  evento.preventDefault();
  $("ed-error").hidden = true;
  const error = (mensaje) => {
    $("ed-error").textContent = mensaje;
    $("ed-error").hidden = false;
  };

  const nombre = $("ed-nombre").value.trim().replace(/\s+/g, " ");
  const precio = $("ed-precio").value.trim();
  const oferta = $("ed-oferta").value.trim();

  if (nombre.length < 3) return error("El nombre debe tener al menos 3 caracteres.");
  if (!dosDecimales(precio) || Number(precio) <= 0) return error("Escribe un precio válido (máximo 2 decimales).");
  if (oferta && (!dosDecimales(oferta) || Number(oferta) <= 0)) return error("Escribe un precio de oferta válido o déjalo vacío.");
  if (oferta && Number(oferta) >= Number(precio)) return error("La oferta debe ser menor que el precio normal.");

  const boton = $("ed-guardar");
  boton.disabled = true;
  boton.textContent = "Guardando...";
  try {
    const r = await api("/admin/productos/" + productoEd.id, {
      metodo: "PUT",
      datos: {
        nombre,
        descripcion: $("ed-descripcion").value.trim(),
        categoria_id: $("ed-categoria").value,
        precio,
        precio_oferta: oferta,
        productor_id: $("ed-productor").value,
      },
    });
    $("dlg-producto").close();
    mostrarOk(r.mensaje);
    await recargar();
  } catch (e) {
    error(e.message);
  } finally {
    boton.disabled = false;
    boton.textContent = "Guardar cambios";
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

  // Filtros (se aplican sin volver a pedir datos a la API)
  $("buscar").addEventListener("input", pintarTabla);
  $("filtro-categoria").addEventListener("change", pintarTabla);
  $("filtro-estado").addEventListener("change", pintarTabla);

  // Tabla: interruptores y botón editar
  $("tabla-productos-admin").addEventListener("change", alCambiarInterruptor);
  $("tabla-productos-admin").addEventListener("click", (evento) => {
    const boton = evento.target.closest("button[data-editar]");
    if (!boton) return;
    const producto = productos.find((p) => String(p.id) === boton.dataset.editar);
    if (producto) abrirEditar(producto);
  });

  // Ventana editar
  $("ed-precio").addEventListener("input", actualizarResumenPrecio);
  $("ed-oferta").addEventListener("input", actualizarResumenPrecio);
  $("form-producto").addEventListener("submit", guardarProducto);
  $("ed-cancelar").addEventListener("click", () => $("dlg-producto").close());

  // Ventana confirmar (Esc también cuenta como cancelar)
  $("conf-aceptar").addEventListener("click", () => cerrarConfirmacion(true));
  $("conf-cancelar").addEventListener("click", () => cerrarConfirmacion(false));
  $("dlg-confirmar").addEventListener("cancel", (evento) => {
    evento.preventDefault();
    cerrarConfirmacion(false);
  });

  await recargar();
})();