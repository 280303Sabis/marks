"""
Aviso de Privacidad de MARK'S.

Cada vez que cambie el contenido, sube la VERSION aquí. config.py la lee de este
archivo, así se sabe qué versión aceptó cada usuario al registrarse.
"""
VERSION = "1.1"
FECHA = "2026-10-10"
CORREO_CONTACTO = "sabi.isaog@gmail.com"

SECCIONES = [
    {
        "titulo": "1. Responsable de tus datos",
        "texto": ("MARK'S es un proyecto integrador de estudiantes de la Universidad Tecnológica "
                  "Santa Catarina, Nuevo León, México. El equipo de MARK'S es responsable del uso y "
                  "protección de tus datos personales, conforme a la Ley Federal de Protección de "
                  "Datos Personales en Posesión de los Particulares."),
    },
    {
        "titulo": "2. Datos que recabamos",
        "texto": ("Datos de identificación y contacto: nombre, apellidos, fecha de nacimiento, "
                  "sexo (puedes elegir \"Prefiero no decirlo\"), correo electrónico y "
                  "teléfono (opcional). Datos de uso: sucursal elegida, productos escaneados, "
                  "compras, puntos de lealtad y cupones. Datos de seguridad: fecha y hora de "
                  "inicios de sesión y dirección IP. No recabamos datos personales sensibles. "
                  "Los datos de tu tarjeta no se guardan en MARK'S."),
    },
    {
        "titulo": "3. Para qué usamos tus datos",
        "texto": ("Finalidades necesarias: crear y proteger tu cuenta, comprobar que eres mayor "
                  "de edad (18 años o más), procesar tus compras, generar tu ticket digital y tu "
                  "código QR de salida, y administrar tus puntos de lealtad. Finalidades "
                  "adicionales: enviarte avisos sobre promociones de productores locales de Nuevo "
                  "León y promociones de cumpleaños, y elaborar estadísticas generales sin "
                  "identificarte (por ejemplo, por rango de edad o sexo). Puedes negarte a las "
                  "finalidades adicionales sin que esto afecte el servicio."),
    },
    {
        "titulo": "4. Con quién compartimos tus datos",
        "texto": ("No vendemos ni rentamos tus datos. Solo se comparten con el procesador de pagos "
                  "para completar una compra, o cuando una autoridad competente lo solicite "
                  "conforme a la ley."),
    },
    {
        "titulo": "5. Cómo protegemos tus datos",
        "texto": ("Tu contraseña se guarda cifrada y nadie del equipo puede verla. Tu cuenta se "
                  "bloquea temporalmente después de 3 intentos fallidos. Los códigos de "
                  "verificación caducan en 15 minutos y sirven una sola vez. Registramos los "
                  "accesos para detectar usos indebidos."),
    },
    {
        "titulo": "6. Tus derechos ARCO",
        "texto": ("Tienes derecho a Acceder a tus datos, Rectificarlos si son incorrectos, "
                  "Cancelarlos (eliminar tu cuenta) y Oponerte a su uso para finalidades "
                  "adicionales. Desde la sección Perfil de la app puedes descargar una copia de tus "
                  "datos y eliminar tu cuenta. También puedes escribirnos a " + CORREO_CONTACTO + "."),
    },
    {
        "titulo": "7. Eliminación de tu cuenta",
        "texto": ("Al eliminar tu cuenta borramos tu nombre, correo, teléfono, fecha de "
                  "nacimiento, sexo, puntos y cupones. "
                  "Los registros de compras se conservan sin datos que te identifiquen, solo para "
                  "fines contables y estadísticos."),
    },
    {
        "titulo": "8. Uso de tecnologías",
        "texto": ("La app guarda en tu celular un token de sesión para que no tengas que iniciar "
                  "sesión cada vez. El token caduca en 12 horas y se invalida si cambias tu "
                  "contraseña o cierras sesión en todos tus dispositivos."),
    },
    {
        "titulo": "9. Cambios a este aviso",
        "texto": ("Si este aviso cambia, te lo mostraremos en la app y te pediremos aceptarlo de "
                  "nuevo. Versión vigente: " + VERSION + ", publicada el " + FECHA + "."),
    },
]


def como_diccionario():
    return {"version": VERSION, "fecha": FECHA, "contacto": CORREO_CONTACTO, "secciones": SECCIONES}