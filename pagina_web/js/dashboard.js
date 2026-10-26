/*
  dashboard.js - Panel de la alianza
  -----------------------------------
  Lo usan dashboard.html, productos-vendidos.html y recuperar.html.
  1. Protege la página: sin sesión de ADMIN regresa a index.html.
  2. Hace funcionar el botón "Cerrar sesión".
  3. Llena la página con los datos reales de la API (las mismas ventas
     e inventario que usa la app). Si no hay ventas, se queda en blanco.
*/

// ---------- Ayudantes ----------
const $ = (id) => document.getElementById(id);

function dinero(n) {
  return "$" + Number(n || 0).toLocaleString("es-MX", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

// Piezas sin decimales; kilos con hasta 3 decimales.
function cantidad(n) {
  return Number(n || 0).toLocaleString("es-MX", { maximumFractionDigits: 3 });
}

function unidad(p) {
  return p.tipo_venta === "GRANEL" ? " kg" : "";
}

// Evita que un nombre con < o > se interprete como HTML.
function texto(t) {
  const d = document.createElement("div");
  d.textContent = t == null ? "" : String(t);
  return d.innerHTML;
}

// Iniciales para el cuadro de la portada: "Supermercados del Norte" -> "SN"
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

// ---------- Aviso cuando la API falla ----------
function mostrarError(e) {
  const aviso = $("aviso-api");
  let mensaje = e.message || "No se pudieron cargar los datos.";
  if (e.estado === 404) {
    mensaje = "El servidor todavía no tiene la versión con el panel de alianzas. Hay que desplegar la API nueva en Render.";
  }
  aviso.innerHTML = '<i class="ph ph-warning-circle" aria-hidden="true"></i><span>' + texto(mensaje) + "</span>";
  aviso.hidden = false;
  // Quitar las filas de "cargando" para que no se queden parpadeando
  document.querySelectorAll(".adm-cargando").forEach((fila) => fila.remove());
  if ($("mas-vendido")) $("mas-vendido").textContent = "Sin datos por ahora.";
}

function ocultarError() {
  $("aviso-api").hidden = true;
}

// ---------- Sucursal elegida (se recuerda mientras la pestaña esté abierta) ----------
const SUCURSAL_KEY = "marks_admin_sucursal";

function sucursalElegida() {
  return sessionStorage.getItem(SUCURSAL_KEY) || "";
}

function pintarSucursal(sucursales, actual) {
  const select = $("sucursal");
  select.innerHTML = sucursales
    .map((s) => `<option value="${s.id}">${texto(s.nombre)}</option>`)
    .join("");
  select.value = String(actual.id);
  $("sucursal-direccion").textContent = [actual.direccion, actual.municipio].filter(Boolean).join(", ");
}

// ---------- dashboard.html ----------
async function cargarInicio() {
  const r = await api("/admin/resumen?sucursal_id=" + sucursalElegida());
  pintarSucursal(r.sucursales, r.sucursal);

  $("ventas-hoy").textContent = dinero(r.hoy.total);
  $("ventas-hoy-detalle").textContent = r.hoy.compras
    ? `${r.hoy.compras} compra(s) · los clientes ahorraron ${dinero(r.hoy.ahorro)}`
    : "Sin ventas registradas hoy";
  $("kpi-compras").textContent = r.hoy.compras;
  $("kpi-unidades").textContent = cantidad(r.hoy.unidades);
  $("kpi-caducar").textContent = r.por_caducar;
  $("kpi-sin-stock").textContent = r.sin_stock;

  const vendidos = r.productos.filter((p) => p.vendidas > 0);
  $("tabla-productos").innerHTML = vendidos.length
    ? vendidos.map((p) => `<tr>
          <td><span class="adm-producto">${texto(p.nombre)}</span>
              <span class="adm-sub">${texto(p.categoria || "Sin categoría")}</span></td>
          <td class="num">${dinero(p.precio)}${p.tipo_venta === "GRANEL" ? " / kg" : ""}</td>
          <td class="num"><strong>${cantidad(p.vendidas)}${unidad(p)}</strong></td>
          <td class="num">${cantidad(p.stock)}${unidad(p)}</td>
        </tr>`).join("")
    : filaVacia(4, "shopping-bag", "Aún no hay ventas hoy", "Los productos aparecerán aquí cuando los clientes paguen en la app.");

  $("mas-vendido").className = "";
  $("mas-vendido").innerHTML = r.mas_vendido
    ? `<div class="adm-destacado">
         <span class="adm-destacado-icono"><i class="ph ph-fire" aria-hidden="true"></i></span>
         <div>
           <strong>${texto(r.mas_vendido.nombre)}</strong>
           <span class="cl-texto-sec">${cantidad(r.mas_vendido.vendidas)}${r.mas_vendido.tipo_venta === "GRANEL" ? " kg" : " unidades"} vendidas hoy</span>
         </div>
       </div>`
    : '<p class="adm-vacio-corto">Se calcula con las ventas reales de hoy.</p>';

  // Gráfica de barras de los últimos 7 días (el último es hoy)
  const maximo = Math.max(...r.demanda.map((d) => d.unidades));
  if (maximo > 0) {
    $("grafica-demanda").innerHTML = `<div class="adm-grafica">
      ${r.demanda.map((d, i) => {
        const alto = d.unidades > 0 ? Math.max(6, Math.round((d.unidades / maximo) * 120)) : 3;
        const dia = new Date(d.dia + "T12:00:00").toLocaleDateString("es-MX", { weekday: "short" }).replace(".", "");
        const hoy = i === r.demanda.length - 1 ? " hoy" : "";
        return `<div class="adm-grafica-col${hoy}" title="${d.dia}: ${cantidad(d.unidades)} unidades">
                  <span class="adm-grafica-valor">${d.unidades > 0 ? cantidad(d.unidades) : ""}</span>
                  <span class="adm-grafica-barra" style="height:${alto}px"></span>
                  <span class="adm-grafica-dia">${hoy ? "Hoy" : dia}</span>
                </div>`;
      }).join("")}</div>
      <p class="adm-nota-grafica">Unidades vendidas por día (piezas y kilos).</p>`;
  } else {
    $("grafica-demanda").innerHTML = '<p class="adm-vacio-corto" style="margin-top:12px">Sin ventas en los últimos 7 días.</p>';
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

  pintarSucursal(r.sucursales, r.sucursal);
  if (!categoriasCargadas) {
    $("categoria").innerHTML = '<option value="todas">Todas las categorías</option>' +
      r.categorias.map((c) => `<option value="${c.id}">${texto(c.nombre)}</option>`).join("");
    categoriasCargadas = true;
  }

  const ingreso = r.ranking.reduce((suma, p) => suma + Number(p.total), 0);
  $("kpi-ingreso-total").textContent = dinero(ingreso);
  $("kpi-ingreso-nota").textContent = r.ranking.length
    ? `${r.ranking.length} producto(s) vendidos en el periodo`
    : "Sin ventas en el periodo";

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
          <td class="centro"><span class="adm-posicion${i < 3 ? " top" : ""}">${i + 1}</span></td>
          <td><span class="adm-producto">${texto(p.nombre)}</span>
              <span class="adm-sub">${texto(p.categoria || "Sin categoría")}</span></td>
          <td class="num">${dinero(p.precio)}${p.tipo_venta === "GRANEL" ? " / kg" : ""}</td>
          <td class="num"><strong>${cantidad(p.unidades)}${unidad(p)}</strong></td>
          <td><div class="adm-barra">
                <div class="adm-barra-fondo"><div class="adm-barra-relleno" style="width:${p.participacion}%"></div></div>
                <span>${p.participacion}%</span>
              </div></td>
          <td class="num"><strong>${dinero(p.total)}</strong></td>
        </tr>`).join("")
    : filaVacia(6, "trophy", "Aún no hay productos vendidos", "El ranking se llena con las compras reales de la sucursal.");
}

// ---------- recuperar.html (historial de compras) ----------
const ESTADOS = {
  PAGADA: ["pagada", "clock", "Pagada"],
  VALIDADA: ["validada", "check-circle", "Validada"],
  CANCELADA: ["cancelada", "x-circle", "Cancelada"],
};

function fechaCorta(texto) {
  // "2026-10-25 14:32" -> "25 oct 2026, 14:32"
  if (!texto) return "";
  const [dia, hora] = texto.split(" ");
  const f = new Date(dia + "T12:00:00").toLocaleDateString("es-MX", { day: "numeric", month: "short", year: "numeric" });
  return f.replace(".", "") + (hora ? ", " + hora : "");
}

async function cargarHistorial() {
  const filtros = new URLSearchParams({
    sucursal_id: sucursalElegida(),
    periodo: $("periodo").value,
    estado: $("estado").value,
    buscar: $("buscar").value.trim(),
  });
  const r = await api("/admin/ventas?" + filtros);

  pintarSucursal(r.sucursales, r.sucursal);
  $("kpi-ingreso").textContent = dinero(r.ingreso);
  $("kpi-ingreso-nota").textContent = r.compras ? `${r.compras} compra(s) en el periodo` : "Sin compras en el periodo";
  $("kpi-compras").textContent = r.compras;
  $("kpi-ticket-promedio").textContent = dinero(r.ticket_promedio);
  $("kpi-clientes").textContent = r.clientes;
  $("kpi-validadas").textContent = r.ventas.filter((v) => v.estado === "VALIDADA").length;

  $("tabla-historial").innerHTML = r.ventas.length
    ? r.ventas.map((v) => {
        const [clase, icono, nombre] = ESTADOS[v.estado] || ["", "circle", v.estado];
        return `<tr>
          <td><span class="adm-folio">${texto(v.folio)}</span></td>
          <td>${texto(fechaCorta(v.fecha))}</td>
          <td><span class="adm-producto">${texto(v.cliente)}</span>
              <span class="adm-sub">${texto(v.correo)}</span></td>
          <td class="num">${v.articulos}</td>
          <td class="num"><strong>${dinero(v.total)}</strong></td>
          <td><span class="adm-estado ${clase}"><i class="ph ph-${icono}" aria-hidden="true"></i>${texto(nombre)}</span></td>
        </tr>`;
      }).join("")
    : filaVacia(6, "receipt", "Aún no hay compras", "Las compras pagadas en la app aparecerán aquí.");
}

// ---------- Arranque ----------
(async () => {
  const usuario = await Sesion.proteger(["ADMIN"], "index.html");
  if (!usuario) return;   // ya se está regresando al acceso

  $("btn-cerrar-sesion").addEventListener("click", (evento) => {
    evento.preventDefault();
    Sesion.salir();
  });

  // Nombre de la alianza (es el nombre de la cuenta con la que entró)
  const nombre = [usuario.nombre, usuario.apellidos].filter(Boolean).join(" ");
  $("alianza-nombre").textContent = nombre || "Mi alianza";
  $("alianza-iniciales").textContent = iniciales(nombre);

  // Cada página tiene su propia tabla; según cuál exista se cargan sus datos.
  let cargar = null;
  if ($("tabla-productos")) cargar = cargarInicio;
  else if ($("tabla-ranking")) cargar = cargarMasVendidos;
  else if ($("tabla-historial")) cargar = cargarHistorial;
  if (!cargar) return;

  const recargar = () => cargar().then(ocultarError).catch(mostrarError);

  $("sucursal").addEventListener("change", () => {
    sessionStorage.setItem(SUCURSAL_KEY, $("sucursal").value);
    recargar();
  });

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
