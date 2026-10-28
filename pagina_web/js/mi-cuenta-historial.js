/*
  mi-cuenta-historial.js - Pestañas de Mi cuenta (PASO W14)
  ----------------------------------------------------------
  Lo usa mi-cuenta.html, después de js/mi-cuenta.js (que sigue manejando
  "Mi perfil" sin cambios). Todo va dentro de una función para no chocar
  con los nombres de mi-cuenta.js.

  1. Pestañas: Mi perfil | Mis compras | Mis puntos | Mis opiniones.
     Se recuerda la última pestaña mientras la sesión esté abierta.
     También se puede abrir directo: mi-cuenta.html#compras
  2. Mis compras: resumen, lista y el ticket de cada compra.
     Si la compra sigue "Por salir", el ticket muestra su QR para el guardia.
  3. Mis puntos: cómo se ganan y usan, y el estado de cuenta
     (también los ajustes que hace MARK'S, con su motivo).
  4. Mis opiniones: las que escribió (incluidas las ocultas) y los
     productos que le faltan por calificar. Se escriben desde la app.

  Rutas de la API que usa (las mismas de la app):
    GET /compras             GET /compras/<folio>
    GET /puntos/movimientos  GET /opiniones/mias
*/
(() => {
  const el = (id) => document.getElementById(id);
  const PESTANA_KEY = "marks_cuenta_pestana";
  const PESTANAS = ["perfil", "compras", "puntos", "opiniones"];
  const MESES = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];

  // ---------- Ayudantes ----------
  function texto(t) {
    const d = document.createElement("div");
    d.textContent = t == null ? "" : String(t);
    return d.innerHTML;
  }

  function dinero(n) {
    return "$" + Number(n || 0).toLocaleString("es-MX", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }

  function numero(n) {
    return Number(n || 0).toLocaleString("es-MX");
  }

  function cantidad(n, tipo) {
    const valor = Number(n || 0).toLocaleString("es-MX", { maximumFractionDigits: 3 });
    return tipo === "GRANEL" ? valor + " kg" : valor + " pza";
  }

  // "2026-10-27T12:30:33" -> "27 oct 2026, 12:30" (la API ya la manda con hora de Monterrey)
  function fecha(iso) {
    if (!iso) return "";
    const [dia, hora = ""] = String(iso).split("T");
    const [a, m, d] = dia.split("-").map(Number);
    return `${d} ${MESES[m - 1]} ${a}` + (hora ? ", " + hora.slice(0, 5) : "");
  }

  function aviso(id, error) {
    const caja = el(id);
    caja.textContent = error ? (error.message || "No se pudo cargar la información.") : "";
    caja.hidden = !error;
  }

  function vacio(icono, titulo, detalle) {
    return `<li class="cth-vacio"><i class="ph ph-${icono}" aria-hidden="true"></i><strong>${texto(titulo)}</strong>${texto(detalle)}</li>`;
  }

  const ESTADOS = {
    PAGADA: ["por-salir", "Por salir"],
    VALIDADA: ["salio", "Ya salió"],
    CANCELADA: ["cancelada", "Cancelada"],
  };

  function insigniaEstado(estado) {
    const [clase, etiqueta] = ESTADOS[estado] || ["gris", estado];
    return `<span class="cth-insignia ${clase}">${etiqueta}</span>`;
  }

  // ---------- 1. Pestañas ----------
  const cargadas = {};

  function guardarPestana(nombre) {
    try { sessionStorage.setItem(PESTANA_KEY, nombre); } catch (e) { /* sin almacenamiento */ }
  }

  function pestanaInicial() {
    const desdeUrl = location.hash.replace("#", "");
    if (PESTANAS.includes(desdeUrl)) return desdeUrl;
    try {
      const guardada = sessionStorage.getItem(PESTANA_KEY);
      if (PESTANAS.includes(guardada)) return guardada;
    } catch (e) { /* sin almacenamiento */ }
    return "perfil";
  }

  function abrirPestana(nombre) {
    document.querySelectorAll(".cth-pestana").forEach((b) => {
      const activa = b.dataset.pestana === nombre;
      b.classList.toggle("activa", activa);
      b.setAttribute("aria-selected", activa ? "true" : "false");
    });
    document.querySelectorAll("[data-panel]").forEach((p) => {
      p.hidden = p.dataset.panel !== nombre;
    });
    guardarPestana(nombre);
    history.replaceState(null, "", nombre === "perfil" ? location.pathname : "#" + nombre);

    if (!cargadas[nombre]) {
      cargadas[nombre] = true;
      if (nombre === "compras") cargarCompras();
      if (nombre === "puntos") cargarPuntos();
      if (nombre === "opiniones") cargarOpiniones();
    }
  }

  // ---------- 2. Mis compras ----------
  let compras = [];

  function filaCompra(c) {
    const puntos = c.puntos_ganados ? `<small>+${numero(c.puntos_ganados)} puntos</small>` : "";
    return `<li>
        <button type="button" class="cth-compra" data-folio="${texto(c.folio)}">
          <span>
            <span class="cth-folio">${texto(c.folio)}</span> ${insigniaEstado(c.estado)}
            <span class="cth-meta">${texto(fecha(c.pagada_en))} · ${texto(c.sucursal)} · ${numero(c.articulos)} artículo${c.articulos === 1 ? "" : "s"}</span>
          </span>
          <span class="cth-total">${dinero(c.total)}${puntos}</span>
          <i class="ph ph-caret-right cth-flecha" aria-hidden="true"></i>
        </button>
      </li>`;
  }

  function pintarContador(porSalir) {
    const contador = el("cth-por-salir");
    contador.textContent = porSalir.length;
    contador.hidden = !porSalir.length;
    contador.title = porSalir.length ? "Compras por salir" : "";
  }

  async function cargarCompras() {
    try {
      const r = await api("/compras?limite=100");
      compras = r.compras;
      pintarContador(r.por_salir);
      aviso("compras-aviso", null);

      const validas = compras.filter((c) => c.estado !== "CANCELADA");
      const gastado = validas.reduce((s, c) => s + Number(c.total), 0);
      const ganados = validas.reduce((s, c) => s + Number(c.puntos_ganados || 0), 0);
      let resumen = "";
      if (compras.length) {
        resumen = `<div class="cth-dato"><span>Compras</span><strong>${numero(validas.length)}</strong></div>
          <div class="cth-dato"><span>Total pagado</span><strong>${dinero(gastado)}</strong></div>
          <div class="cth-dato"><span>Puntos ganados</span><strong>${numero(ganados)}</strong></div>`;
      }
      el("compras-resumen").innerHTML = resumen;

      const lista = el("lista-compras");
      if (!compras.length) {
        lista.innerHTML = vacio("shopping-cart", "Todavía no tienes compras",
          "Escanea tus productos con la app de MARK'S y paga sin hacer fila.");
        return;
      }
      const avisoSalida = r.por_salir.length
        ? `<li class="cth-aviso-fila"><div class="cth-aviso-salida">
             <i class="ph ph-qr-code" aria-hidden="true"></i>
             <span>Tienes ${r.por_salir.length === 1 ? "1 compra lista" : r.por_salir.length + " compras listas"} para salir. Abre el ticket y muestra el QR al guardia.</span>
           </div></li>`
        : "";
      lista.innerHTML = avisoSalida + compras.map(filaCompra).join("");
    } catch (e) {
      cargadas.compras = false;
      aviso("compras-aviso", e);
      el("lista-compras").innerHTML = "";
    }
  }

  function dibujarQR(textoQR, folio) {
    const caja = el("tk-qr-imagen");
    if (typeof qrcode === "function") {
      try {
        const qr = qrcode(0, "M");
        qr.addData(textoQR);
        qr.make();
        caja.innerHTML = qr.createSvgTag({ cellSize: 4, margin: 0, scalable: true });
        return;
      } catch (e) { /* si falla, se muestra el folio */ }
    }
    caja.innerHTML = `<span class="cth-qr-texto">No se pudo dibujar el QR. Dile al guardia tu folio: <strong>${texto(folio)}</strong></span>`;
  }

  async function abrirTicket(folio) {
    const dialogo = el("dlg-ticket");
    el("tk-folio").textContent = folio;
    el("tk-datos").textContent = "Cargando ticket…";
    el("tk-qr").hidden = true;
    el("tk-estado").innerHTML = "";
    el("tk-lineas").innerHTML = "";
    el("tk-totales").innerHTML = "";
    el("tk-pie").textContent = "";
    dialogo.showModal();

    try {
      const { venta: v } = await api("/compras/" + encodeURIComponent(folio));
      el("tk-datos").textContent = `${v.sucursal} · ${fecha(v.pagada_en)}`;

      if (v.estado === "PAGADA" && v.qr) {
        el("tk-qr").hidden = false;
        dibujarQR(v.qr, v.folio);
      }
      el("tk-estado").innerHTML = v.estado === "VALIDADA"
        ? `${insigniaEstado(v.estado)} <span class="cth-validada">el ${texto(fecha(v.validada_en))}</span>`
        : insigniaEstado(v.estado);

      el("tk-lineas").innerHTML = v.lineas.map((l) => {
        const oferta = Number(l.importe) < Number(l.importe_normal)
          ? `<span class="antes">${dinero(l.importe_normal)}</span>` : "";
        return `<li>
            <span>${texto(l.nombre)}${l.es_local ? '<span class="cth-local">Local NL</span>' : ""}</span>
            <span class="detalle">${cantidad(l.cantidad, l.tipo_venta)} × ${dinero(l.precio_final)}${l.tipo_venta === "GRANEL" ? "/kg" : ""}</span>
            <span class="importe">${dinero(l.importe)}${oferta}</span>
          </li>`;
      }).join("");

      let totales = `<dt>Subtotal</dt><dd>${dinero(v.subtotal)}</dd>`;
      if (Number(v.ahorro) > 0) totales += `<dt>Ahorro en ofertas</dt><dd class="verde">−${dinero(v.ahorro)}</dd>`;
      if (Number(v.puntos_usados) > 0) {
        totales += `<dt>Puntos usados (${numero(v.puntos_usados)})</dt><dd class="verde">−${dinero(v.descuento_puntos)}</dd>`;
      }
      totales += `<dt class="total">Total pagado</dt><dd class="total">${dinero(v.total)}</dd>`;
      el("tk-totales").innerHTML = totales;

      const tarjeta = v.tarjeta ? `${v.tarjeta.marca} terminación ${v.tarjeta.ultimos4}` : "";
      const puntos = v.puntos_ganados ? ` · Ganaste ${numero(v.puntos_ganados)} puntos` : "";
      el("tk-pie").textContent = tarjeta + puntos;
    } catch (e) {
      el("tk-datos").textContent = e.message || "No se pudo cargar el ticket.";
    }
  }

  // ---------- 3. Mis puntos ----------
  function itemMovimiento(m) {
    const mas = m.puntos > 0;
    const ajuste = m.tipo === "AJUSTE";
    const tipo = { GANADOS: "Ganados en compra", CANJEADOS: "Usados en compra", AJUSTE: "Ajuste de MARK'S" }[m.tipo] || m.tipo;
    const folio = m.folio && !ajuste ? ` · ${texto(m.folio)}` : "";
    return `<li class="cth-movimiento">
        <span class="cth-mov-nota">${ajuste ? '<span class="cth-etiqueta-ajuste">Ajuste</span>' : ""}${texto(m.nota || tipo)}</span>
        <span class="cth-mov-meta">${texto(tipo)} · ${texto(fecha(m.fecha))}${folio}</span>
        <span class="cth-mov-puntos ${mas ? "mas" : "menos"}">${mas ? "+" : "−"}${numero(Math.abs(m.puntos))}
          <small>Saldo ${numero(m.saldo_final)}</small></span>
      </li>`;
  }

  async function cargarPuntos() {
    try {
      const r = await api("/puntos/movimientos?limite=100");
      aviso("puntos-aviso", null);
      el("cliente-puntos").textContent = numero(r.saldo);   // saldo al día en la tarjeta de arriba

      const g = r.reglas;
      el("puntos-reglas").innerHTML = `
        <div class="cth-regla"><i class="ph ph-shopping-bag" aria-hidden="true"></i>
          <div><strong>Gana</strong><span>1 punto por cada $${numero(g.pesos_por_punto)} que pagas con tarjeta.</span></div></div>
        <div class="cth-regla"><i class="ph ph-plant" aria-hidden="true"></i>
          <div><strong>Local cuenta ×${numero(g.multiplicador_local)}</strong><span>Los productos de Nuevo León te dan el doble.</span></div></div>
        <div class="cth-regla"><i class="ph ph-ticket" aria-hidden="true"></i>
          <div><strong>Usa</strong><span>${numero(g.puntos_por_bloque)} puntos = $${numero(g.valor_bloque)} de descuento, hasta el ${numero(g.max_porcentaje_canje)}% de tu compra.</span></div></div>`;

      el("lista-puntos").innerHTML = r.movimientos.length
        ? r.movimientos.map(itemMovimiento).join("")
        : vacio("coins", "Todavía no tienes movimientos", "Cada compra con la app te da puntos.");
    } catch (e) {
      cargadas.puntos = false;
      aviso("puntos-aviso", e);
      el("lista-puntos").innerHTML = "";
    }
  }

  // ---------- 4. Mis opiniones ----------
  function estrellas(n) {
    let html = "";
    for (let i = 1; i <= 5; i++) html += `<span${i > n ? ' class="apagada"' : ""}>★</span>`;
    return `<span class="cth-estrellas" title="${n} de 5 estrellas">${html}</span>`;
  }

  function urlFoto(url) {
    return url.startsWith("http") ? url : API_URL.replace(/\/api\/?$/, "") + url;
  }

  function itemOpinion(o) {
    const oculta = o.estado === "OCULTA";
    const fotos = !oculta && o.fotos && o.fotos.length
      ? `<div class="cth-fotos">${o.fotos.map((f) => `<img src="${texto(urlFoto(f.url))}" alt="Foto de tu opinión" loading="lazy">`).join("")}</div>`
      : "";
    return `<li class="cth-opinion">
        <div class="cth-opinion-cabeza">
          ${estrellas(o.estrellas)}
          <span class="cth-opinion-producto">${texto(o.producto)}</span>
          ${oculta ? '<span class="cth-insignia oculta">Oculta</span>' : ""}
          ${o.editada ? '<span class="cth-insignia gris">Editada</span>' : ""}
        </div>
        ${o.comentario ? `<p>${texto(o.comentario)}</p>` : '<p class="cth-meta">Solo calificaste con estrellas.</p>'}
        ${fotos}
        ${oculta ? '<p class="cth-nota-oculta">MARK\'S ocultó esta opinión porque no cumple las reglas. Solo tú la ves.</p>' : ""}
        <span class="cth-meta">${texto(fecha(o.creada_en))}</span>
      </li>`;
  }

  async function cargarOpiniones() {
    try {
      const r = await api("/opiniones/mias");
      aviso("opiniones-aviso", null);
      el("lista-opiniones").innerHTML = r.publicadas.length
        ? r.publicadas.map(itemOpinion).join("")
        : vacio("star", "Todavía no escribes opiniones", "Después de comprar, califica tus productos desde el ticket en la app.");
      el("caja-pendientes").hidden = !r.pendientes.length;
      el("lista-pendientes").innerHTML = r.pendientes.map((p) => `<li>${texto(p.nombre)}</li>`).join("");
    } catch (e) {
      cargadas.opiniones = false;
      aviso("opiniones-aviso", e);
      el("lista-opiniones").innerHTML = "";
    }
  }

  // ---------- Arranque ----------
  const u = Sesion.usuario();
  if (!Sesion.token() || !u || u.rol !== "CLIENTE") return;   // mi-cuenta.js ya regresa al acceso

  document.querySelectorAll(".cth-pestana").forEach((b) => {
    b.addEventListener("click", () => abrirPestana(b.dataset.pestana));
  });
  el("lista-compras").addEventListener("click", (evento) => {
    const fila = evento.target.closest("button[data-folio]");
    if (fila) abrirTicket(fila.dataset.folio);
  });
  el("tk-cerrar").addEventListener("click", () => el("dlg-ticket").close());
  el("dlg-ticket").addEventListener("click", (evento) => {
    if (evento.target === el("dlg-ticket")) el("dlg-ticket").close();   // clic fuera del ticket
  });

  abrirPestana(pestanaInicial());

  // El número de compras "por salir" se ve en la pestaña aunque no esté abierta
  if (!cargadas.compras) {
    api("/compras?limite=100").then((r) => pintarContador(r.por_salir)).catch(() => {});
  }
})();