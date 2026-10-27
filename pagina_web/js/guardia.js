/*
  guardia.js - Pantalla del guardia (PASO W12)
  ---------------------------------------------
  Lo usa guardia.html.
  1. Protege la página: entran GUARDIA y ADMIN (el admin ve además "Panel").
  2. Enciende la cámara y lee el QR de salida con la librería html5-qrcode.
  3. Manda el QR (o el folio escrito) a la API y muestra el resultado en grande:
       verde  = puede salir
       ámbar  = el QR ya se usó (la compra ya salió)
       rojo   = QR no válido, otra sucursal, cancelada o no existe
  4. Muestra lo de hoy en la sucursal: validadas, pagadas sin salir y las últimas.

  La sucursal se recuerda en este dispositivo (el guardia siempre está en la misma).

  Rutas de la API que usa:
    POST /guardia/validar   {qr | folio, sucursal_id}
    GET  /guardia/resumen?sucursal_id=
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

// "2026-10-27 14:32" -> "27 oct, 14:32"
function fechaCorta(textoFecha) {
  if (!textoFecha) return "";
  const [dia, hora] = textoFecha.split(" ");
  const f = new Date(dia + "T12:00:00").toLocaleDateString("es-MX", { day: "numeric", month: "short" });
  return f.replace(".", "") + (hora ? ", " + hora : "");
}

function mostrarError(e) {
  const aviso = $("aviso-api");
  let mensaje = e.message || "No se pudo conectar con la API.";
  if (e.estado === 404) {
    mensaje = "La API todavía no tiene el módulo del guardia. Revisa que estés usando la API nueva (PASO W12).";
  }
  aviso.innerHTML = '<i class="ph ph-warning-circle" aria-hidden="true"></i><span>' + texto(mensaje) + "</span>";
  aviso.hidden = false;
}

function ocultarError() {
  $("aviso-api").hidden = true;
}

// ---------- Sucursal (se recuerda en este dispositivo) ----------
const SUCURSAL_KEY = "marks_guardia_sucursal";

function sucursalGuardada() {
  try {
    return localStorage.getItem(SUCURSAL_KEY) || "";
  } catch (e) {
    return "";
  }
}

function guardarSucursal(id) {
  try {
    localStorage.setItem(SUCURSAL_KEY, id);
  } catch (e) {
    // Sin almacenamiento: se usa la que esté elegida en la lista
  }
}

// ---------- Sonido corto (bien = agudo, mal = grave) ----------
function sonar(bien) {
  try {
    const ctx = new (window.AudioContext || window.webkitAudioContext)();
    const osc = ctx.createOscillator();
    const vol = ctx.createGain();
    osc.frequency.value = bien ? 880 : 220;
    vol.gain.value = 0.08;
    osc.connect(vol);
    vol.connect(ctx.destination);
    osc.start();
    osc.stop(ctx.currentTime + (bien ? 0.15 : 0.4));
  } catch (e) {
    // Sin sonido no pasa nada
  }
}

// ---------- Resultado en pantalla ----------
const ESTILOS = {
  espera:   ["espera", "ph-scan", "Esperando cliente"],
  cargando: ["espera cargando", "ph-circle-notch", "Validando…"],
  ok:       ["ok", "ph-check-circle", "Puede salir"],
  aviso:    ["aviso", "ph-warning", "Este QR ya se usó"],
  error:    ["error", "ph-x-circle", "No puede salir"],
};

const TITULOS_ERROR = {
  QR_INVALIDO: "QR no válido",
  FOLIO_INVALIDO: "Folio incompleto",
  NO_EXISTE: "Compra no encontrada",
  OTRA_SUCURSAL: "Es de otra sucursal",
  CANCELADA: "Compra cancelada",
  SUCURSAL: "Elige la sucursal",
};

let esperandoSiguiente = false;

function pintarResultado(tipo, mensaje, venta, titulo) {
  const [clase, icono, tituloBase] = ESTILOS[tipo];
  $("resultado").className = "cl-tarjeta gda-resultado " + clase;
  $("res-icono").className = "ph " + icono;
  $("res-titulo").textContent = titulo || tituloBase;
  $("res-mensaje").textContent = mensaje;

  $("res-venta").hidden = !venta;
  if (venta) {
    $("res-folio").textContent = venta.folio;
    $("res-cliente").textContent = venta.cliente;
    $("res-articulos").textContent = venta.articulos;
    $("res-total").textContent = dinero(venta.total);
    $("res-extra").textContent = tipo === "aviso" && venta.validada_en
      ? `Salió el ${fechaCorta(venta.validada_en)}${venta.validada_por ? " · validó " + venta.validada_por : ""}.`
      : (venta.pagada_en ? `Pagada el ${fechaCorta(venta.pagada_en)} en ${venta.sucursal}.` : "");
    $("res-productos").innerHTML = (venta.productos || []).map((p) =>
      `<li>${cantidad(p.cantidad)}${p.tipo_venta === "GRANEL" ? " kg" : " pza"} · ${texto(p.nombre)}</li>`).join("");
  }

  esperandoSiguiente = tipo !== "espera" && tipo !== "cargando";
  $("btn-siguiente").hidden = !esperandoSiguiente;

  // En celular, llevar la vista al resultado
  if (esperandoSiguiente && window.innerWidth < 860) {
    $("resultado").scrollIntoView({ behavior: "smooth", block: "center" });
  }
}

function siguienteCliente() {
  pintarResultado("espera", "Escanea el QR o escribe el folio para validar la salida.");
  $("folio").value = "";
  reanudarCamara();
}

// ---------- Validar ----------
let validando = false;

async function validar(datos) {
  if (validando) return;
  validando = true;
  pausarCamara();
  pintarResultado("cargando", "Revisando la compra…");
  try {
    const r = await api("/guardia/validar", {
      metodo: "POST",
      datos: { ...datos, sucursal_id: $("sucursal").value },
    });
    pintarResultado("ok", "La compra está pagada. Revisa la bolsa y deja salir al cliente.", r.venta);
    sonar(true);
    cargarResumen();
  } catch (e) {
    const codigo = e.datos && e.datos.codigo;
    if (codigo === "YA_VALIDADA") {
      pintarResultado("aviso", "La compra ya salió de la tienda. No dejes pasar otra vez con este QR.", e.datos.venta);
    } else if (e.estado === 0) {
      pintarResultado("error", "No hay conexión con la API. Intenta de nuevo.", null, "Sin conexión");
    } else {
      pintarResultado("error", e.message, (e.datos && e.datos.venta) || null, TITULOS_ERROR[codigo]);
    }
    sonar(false);
  } finally {
    validando = false;
  }
}

// ---------- Cámara (html5-qrcode) ----------
let lector = null;
let camaraEncendida = false;
let ultimoTexto = "";
let ultimoMomento = 0;

function textoBotonCamara() {
  $("btn-camara").querySelector("span").textContent = camaraEncendida ? "Apagar cámara" : "Encender cámara";
  $("visor-apagado").hidden = camaraEncendida;
}

function alLeerQR(textoQR) {
  // Evitar leer el mismo QR varias veces seguidas
  const ahora = Date.now();
  if (textoQR === ultimoTexto && ahora - ultimoMomento < 4000) return;
  ultimoTexto = textoQR;
  ultimoMomento = ahora;
  if (esperandoSiguiente || validando) return;
  validar({ qr: textoQR });
}

async function encenderCamara() {
  if (typeof Html5Qrcode === "undefined") {
    $("visor-texto").textContent = "No se pudo cargar el lector de QR. Revisa el internet o escribe el folio.";
    return;
  }
  try {
    lector = lector || new Html5Qrcode("lector");
    await lector.start(
      { facingMode: "environment" },
      { fps: 10, qrbox: (ancho, alto) => {
          const lado = Math.floor(Math.min(ancho, alto) * 0.7);
          return { width: lado, height: lado };
        } },
      alLeerQR,
      () => {},   // cuadro sin QR: no hacer nada
    );
    camaraEncendida = true;
  } catch (e) {
    camaraEncendida = false;
    $("visor-texto").textContent = "No se pudo usar la cámara. Da permiso en el navegador (ícono de la cámara junto a la dirección) o escribe el folio.";
  }
  textoBotonCamara();
}

async function apagarCamara() {
  if (lector && camaraEncendida) {
    try {
      await lector.stop();
    } catch (e) {
      // ya estaba detenida
    }
  }
  camaraEncendida = false;
  $("visor-texto").textContent = "La cámara está apagada";
  textoBotonCamara();
}

function pausarCamara() {
  if (lector && camaraEncendida) {
    try { lector.pause(true); } catch (e) { /* no estaba leyendo */ }
  }
}

function reanudarCamara() {
  if (lector && camaraEncendida) {
    try { lector.resume(); } catch (e) { /* no estaba pausada */ }
  }
}

// ---------- Hoy en la sucursal ----------
async function cargarResumen() {
  try {
    const r = await api("/guardia/resumen?sucursal_id=" + ($("sucursal").value || sucursalGuardada()));
    if (!$("sucursal").options.length) {
      $("sucursal").innerHTML = r.sucursales.map((s) => `<option value="${s.id}">${texto(s.nombre)}</option>`).join("");
    }
    $("sucursal").value = String(r.sucursal.id);
    guardarSucursal(String(r.sucursal.id));

    $("hoy-validadas").textContent = r.validadas_hoy;
    $("hoy-por-salir").textContent = r.por_salir;
    $("hoy-lista").innerHTML = r.ultimas.length
      ? r.ultimas.map((u) => `<li>
          <span class="hora">${texto(u.hora)}</span>
          <span><span class="folio">${texto(u.folio)}</span> · ${texto(u.cliente)}</span>
          <span class="articulos">${u.articulos} art.</span>
          <strong>${dinero(u.total)}</strong>
        </li>`).join("")
      : '<li class="vacio">Todavía no validas compras hoy en esta sucursal.</li>';
    ocultarError();
  } catch (e) {
    mostrarError(e);
  }
}

// ---------- Arranque ----------
(async () => {
  const usuario = await Sesion.proteger(["GUARDIA", "ADMIN"], "index.html");
  if (!usuario) return;

  $("btn-cerrar-sesion").addEventListener("click", async (evento) => {
    evento.preventDefault();
    await apagarCamara();
    Sesion.salir();
  });

  const nombre = [usuario.nombre, usuario.apellidos].filter(Boolean).join(" ");
  $("gda-guardia").textContent = (usuario.rol === "ADMIN" ? "Administrador: " : "Guardia: ") + (nombre || usuario.correo);
  $("menu-panel").hidden = usuario.rol !== "ADMIN";

  $("sucursal").addEventListener("change", () => {
    guardarSucursal($("sucursal").value);
    siguienteCliente();
    cargarResumen();
  });

  $("btn-camara").addEventListener("click", () => (camaraEncendida ? apagarCamara() : encenderCamara()));
  $("btn-siguiente").addEventListener("click", siguienteCliente);

  $("form-folio").addEventListener("submit", (evento) => {
    evento.preventDefault();
    const folio = $("folio").value.trim().toUpperCase();
    if (!folio) {
      $("folio").focus();
      return;
    }
    validar({ folio });
  });

  // Tecla Enter o Espacio con un resultado en pantalla = siguiente cliente
  document.addEventListener("keydown", (evento) => {
    if (esperandoSiguiente && (evento.key === "Enter" || evento.key === " ") && document.activeElement !== $("folio")) {
      evento.preventDefault();
      siguienteCliente();
    }
  });

  // Apagar la cámara al salir de la página (libera la cámara del equipo)
  window.addEventListener("pagehide", apagarCamara);

  textoBotonCamara();
  await cargarResumen();
})();