/*
  dashboard.js - Vistas del administrador
  ----------------------------------------
  Lo usan dashboard.html, productos-vendidos.html y recuperar.html.
  1. Protege la página: sin sesión de ADMIN regresa a index.html.
  2. Hace funcionar el botón "Cerrar Sesión".
  3. Llena la página con los datos reales de la API (las mismas ventas
     e inventario que usa la app). Si no hay ventas, se queda en blanco.
*/

// ---------- Ayudantes ----------
const $ = (id) => document.getElementById(id);

function dinero(n) {
  return "$" + Number(n || 0).toLocaleString("es-MX", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + " MXN";
}

// Piezas sin decimales; kilos con hasta 3 decimales.
function cantidad(n) {
  return Number(n || 0).toLocaleString("es-MX", { maximumFractionDigits: 3 });
}

// Evita que un nombre con < o > se interprete como HTML.
function texto(t) {
  const d = document.createElement("div");
  d.textContent = t == null ? "" : String(t);
  return d.innerHTML;
}

function filaVacia(columnas, icono, titulo, detalle) {
  return `<tr><td colspan="${columnas}" class="empty-state">
            <span class="empty-icon">${icono}</span>
            <strong>${titulo}</strong><p>${detalle}</p></td></tr>`;
}

// ---------- Sucursal elegida (se recuerda mientras la pestaña esté abierta) ----------
const SUCURSAL_KEY = "marks_admin_sucursal";

function sucursalElegida() {
  return sessionStorage.getItem(SUCURSAL_KEY) || "";
}

// Crea (una sola vez) el selector de sucursal y lo llena con las de la API.
function pintarSelectorSucursal(contenedor, sucursales, actual, alCambiar) {
  let select = $("sucursal");
  if (!select) {
    const grupo = document.createElement("div");
    grupo.className = "filter-group";
    grupo.innerHTML = '<label for="sucursal">Sucursal:</label><select id="sucursal" class="filter-select"></select>';
    contenedor.prepend(grupo);
    select = $("sucursal");
    select.addEventListener("change", () => {
      sessionStorage.setItem(SUCURSAL_KEY, select.value);
      alCambiar();
    });
  }
  select.innerHTML = sucursales
    .map((s) => `<option value="${s.id}">${texto(s.nombre)}</option>`)
    .join("");
  select.value = String(actual);
}

function mostrarError(e) {
  alert(e.message || "No se pudieron cargar los datos");
}

// ---------- dashboard.html ----------
async function cargarInicio() {
  const r = await api("/admin/resumen?sucursal_id=" + sucursalElegida());

  pintarSelectorSucursal(document.querySelector(".admin-header > div"), r.sucursales, r.sucursal.id, cargarInicio);
  $("sucursal-nombre").textContent = r.sucursal.nombre;
  $("sucursal-direccion").textContent = [r.sucursal.direccion, r.sucursal.municipio].filter(Boolean).join(", ");

  $("ventas-hoy").textContent = dinero(r.hoy.total);
  $("ventas-hoy-detalle").textContent = r.hoy.compras
    ? `${r.hoy.compras} compra(s) · ahorro a clientes ${dinero(r.hoy.ahorro)}`
    : "Sin ventas registradas";
  $("kpi-compras").textContent = r.hoy.compras;
  $("kpi-unidades").textContent = cantidad(r.hoy.unidades);
  $("kpi-caducar").textContent = r.por_caducar;
  $("kpi-sin-stock").textContent = r.sin_stock;

  // Tabla: productos de la sucursal (solo si ya hubo ventas hoy se muestran unidades)
  const vendidos = r.productos.filter((p) => p.vendidas > 0);
  $("tabla-productos").innerHTML = vendidos.length
    ? vendidos.map((p) => `<tr>
          <td>${texto(p.nombre)}</td>
          <td>${texto(p.categoria || "Sin categoría")}</td>
          <td>${dinero(p.precio)}${p.tipo_venta === "GRANEL" ? " / kg" : ""}</td>
          <td>${cantidad(p.vendidas)}${p.tipo_venta === "GRANEL" ? " kg" : ""}</td>
        </tr>`).join("")
    : filaVacia(4, "📦", "Aún no hay ventas hoy", "Los productos aparecerán aquí cuando se registren compras en la app.");

  $("mas-vendido").innerHTML = r.mas_vendido
    ? `<strong>${texto(r.mas_vendido.nombre)}</strong>
       <p>${cantidad(r.mas_vendido.vendidas)}${r.mas_vendido.tipo_venta === "GRANEL" ? " kg" : " unidades"} vendidas hoy</p>`
    : "<strong>Sin datos</strong><p>Se calculará con las ventas reales.</p>";

  // Gráfica de barras de los últimos 7 días
  const maximo = Math.max(...r.demanda.map((d) => d.unidades));
  if (maximo > 0) {
    $("grafica-demanda").innerHTML = `<div style="display:flex;align-items:flex-end;gap:8px;height:150px;">
      ${r.demanda.map((d) => {
        const alto = Math.max(4, Math.round((d.unidades / maximo) * 120));
        const dia = new Date(d.dia + "T12:00:00").toLocaleDateString("es-MX", { weekday: "short" });
        return `<div style="flex:1;text-align:center;font-size:12px;color:#555;">
                  <div>${cantidad(d.unidades)}</div>
                  <div title="${d.dia}" style="height:${alto}px;background:#2b581b;border-radius:6px 6px 0 0;margin:4px 0;"></div>
                  <div>${dia}</div></div>`;
      }).join("")}</div>
      <p style="font-size:12px;color:#777;margin-top:8px;">Unidades vendidas por día (últimos 7 días)</p>`;
  } else {
    $("grafica-demanda").innerHTML = `<div class="empty-state"><span class="empty-icon">📊</span>
      <strong>Sin datos para graficar</strong><p>La demanda se mostrará cuando existan ventas.</p></div>`;
  }
}

// ---------- productos-vendidos.html ----------
let categoriasCargadas = false;

async function cargarMasVendidos() {
  const filtros = new URLSearchParams({
    sucursal_id: sucursalElegida(),
    periodo: $("periodo").value,
    buscar: $("buscar").value.trim(),
  });
  if ($("categoria").value !== "todas") filtros.set("categoria", $("categoria").value);
  const r = await api("/admin/mas-vendidos?" + filtros);

  pintarSelectorSucursal(document.querySelector(".filter-bar"), r.sucursales, r.sucursal.id, cargarMasVendidos);
  if (!categoriasCargadas) {
    $("categoria").innerHTML = '<option value="todas">Todas las categorías</option>' +
      r.categorias.map((c) => `<option value="${c.id}">${texto(c.nombre)}</option>`).join("");
    categoriasCargadas = true;
  }

  $("kpi-unidades").textContent = cantidad(r.unidades);
  $("kpi-top-producto").textContent = r.top_producto ? r.top_producto.nombre : "—";
  $("kpi-top-unidades").textContent = r.top_producto
    ? cantidad(r.top_producto.unidades) + (r.top_producto.tipo_venta === "GRANEL" ? " kg vendidos" : " unidades vendidas")
    : "Sin ventas registradas";
  $("kpi-top-categoria").textContent = r.top_categoria ? r.top_categoria.nombre : "—";
  $("kpi-top-categoria-pct").textContent = r.top_categoria
    ? r.top_categoria.participacion + "% de las unidades"
    : "Sin ventas registradas";
  $("kpi-ingreso-top").textContent = dinero(r.top_producto ? r.top_producto.total : 0);

  $("tabla-ranking").innerHTML = r.ranking.length
    ? r.ranking.map((p, i) => `<tr>
          <td style="text-align:center;">${i + 1}</td>
          <td>${texto(p.nombre)}</td>
          <td>${texto(p.categoria || "Sin categoría")}</td>
          <td>${dinero(p.precio)}${p.tipo_venta === "GRANEL" ? " / kg" : ""}</td>
          <td>${cantidad(p.unidades)}${p.tipo_venta === "GRANEL" ? " kg" : ""}</td>
          <td>${p.participacion}%</td>
          <td>${dinero(p.total)}</td>
        </tr>`).join("")
    : filaVacia(7, "🏆", "Aún no hay productos vendidos", "El ranking se llenará con las compras reales de la sucursal.");
}

// ---------- recuperar.html (historial de compras) ----------
const ESTADOS = { PAGADA: "Pagada", VALIDADA: "Validada en salida", CANCELADA: "Cancelada" };

async function cargarHistorial() {
  const filtros = new URLSearchParams({
    sucursal_id: sucursalElegida(),
    periodo: $("periodo").value,
    estado: $("estado").value,
    buscar: $("buscar").value.trim(),
  });
  const r = await api("/admin/ventas?" + filtros);

  pintarSelectorSucursal(document.querySelector(".filter-bar"), r.sucursales, r.sucursal.id, cargarHistorial);
  $("kpi-compras").textContent = r.compras;
  $("kpi-ingreso").textContent = dinero(r.ingreso);
  $("kpi-ticket-promedio").textContent = dinero(r.ticket_promedio);
  $("kpi-clientes").textContent = r.clientes;

  $("tabla-historial").innerHTML = r.ventas.length
    ? r.ventas.map((v) => `<tr>
          <td>${texto(v.folio)}</td>
          <td>${texto(v.fecha)}</td>
          <td>${texto(v.cliente)}<br><small style="color:#777;">${texto(v.correo)}</small></td>
          <td>${v.articulos}</td>
          <td>${dinero(v.total)}</td>
          <td>${ESTADOS[v.estado] || texto(v.estado)}</td>
        </tr>`).join("")
    : filaVacia(6, "🧾", "Aún no hay compras", "Las compras pagadas en la app aparecerán aquí.");
}

// ---------- Arranque ----------
(async () => {
  const usuario = await Sesion.proteger(["ADMIN"], "index.html");
  if (!usuario) return;   // ya se está regresando al acceso

  $("btn-cerrar-sesion").addEventListener("click", (evento) => {
    evento.preventDefault();
    Sesion.salir();
  });

  // Cada página tiene su propia tabla; según cuál exista se cargan sus datos.
  let cargar = null;
  if ($("tabla-productos")) cargar = cargarInicio;
  else if ($("tabla-ranking")) cargar = cargarMasVendidos;
  else if ($("tabla-historial")) cargar = cargarHistorial;
  if (!cargar) return;

  const recargar = () => cargar().catch(mostrarError);

  // Filtros: recargar al cambiar; el buscador espera a que dejes de escribir.
  ["periodo", "categoria", "estado"].forEach((id) => $(id) && $(id).addEventListener("change", recargar));
  if ($("buscar")) {
    let espera;
    $("buscar").addEventListener("input", () => {
      clearTimeout(espera);
      espera = setTimeout(recargar, 400);
    });
  }

  await recargar();
})();
