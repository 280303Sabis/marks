/*
  sesion.js - Manejo de la sesión del portal web de MARK'S
  ---------------------------------------------------------
  Guarda el token, los datos del usuario y la página por la que entró
  (index.html para el personal, acceso-clientes.html para clientes).
  Se usa sessionStorage: la sesión se borra sola al cerrar la pestaña.

  Uso en una página protegida:
    const usuario = await Sesion.proteger(["ADMIN"], "index.html");
*/

const Sesion = {
  _TOKEN: "marks_token",
  _USUARIO: "marks_usuario",
  _ACCESO: "marks_acceso",

  // Guarda la sesión después de un login correcto.
  guardar(token, usuario, paginaAcceso = "index.html") {
    sessionStorage.setItem(this._TOKEN, token);
    sessionStorage.setItem(this._USUARIO, JSON.stringify(usuario));
    sessionStorage.setItem(this._ACCESO, paginaAcceso);
  },

  // Regresa el token, o null si no hay sesión.
  token() {
    return sessionStorage.getItem(this._TOKEN);
  },

  // Regresa los datos del usuario ({id, nombre, correo, rol, puntos}) o null.
  usuario() {
    try {
      return JSON.parse(sessionStorage.getItem(this._USUARIO));
    } catch (e) {
      return null;
    }
  },

  // Página de acceso por la que entró el usuario (a donde regresa al salir).
  paginaAcceso() {
    return sessionStorage.getItem(this._ACCESO) || "index.html";
  },

  // Borra la sesión.
  cerrar() {
    sessionStorage.removeItem(this._TOKEN);
    sessionStorage.removeItem(this._USUARIO);
    sessionStorage.removeItem(this._ACCESO);
  },

  // Cierra la sesión y regresa a la página de acceso por la que entró.
  salir() {
    const pagina = this.paginaAcceso();
    this.cerrar();
    location.replace(pagina);
  },

  // Protege una página. Si no hay sesión o el rol no tiene permiso,
  // manda a paginaAcceso. Si todo está bien, regresa los datos del usuario.
  async proteger(rolesPermitidos, paginaAcceso = "index.html") {
    // Ocultar la página mientras se revisa, para que no se alcance a ver nada.
    document.documentElement.style.visibility = "hidden";

    const u = this.usuario();
    if (!this.token() || !u) {
      this.cerrar();
      location.replace(paginaAcceso);
      return null;
    }
    if (!rolesPermitidos.includes(u.rol)) {
      // Tiene sesión, pero de otro tipo (ej. un cliente en el panel de admin).
      location.replace(paginaAcceso);
      return null;
    }

    try {
      // Confirmar con la API que el token sigue siendo válido.
      const yo = await api("/auth/yo");
      if (!rolesPermitidos.includes(yo.rol)) {
        location.replace(paginaAcceso);
        return null;
      }
      document.documentElement.style.visibility = "visible";
      return yo;
    } catch (e) {
      if (e.estado === 0) {
        // La API está apagada: se muestra la página con un aviso.
        document.documentElement.style.visibility = "visible";
        alert(e.message);
        return u;
      }
      this.cerrar();
      location.replace(paginaAcceso);
      return null;
    }
  },
};