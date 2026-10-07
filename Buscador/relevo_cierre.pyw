import importlib.util as u
import os
s = u.spec_from_file_location("l", os.path.join(os.path.dirname(os.path.abspath(__file__)), "lanzar_buscador.pyw"))
m = u.module_from_spec(s); s.loader.exec_module(m)
p = m.perfil()
m.esperar_cierre(p); m.limpiar_tras_cierre(p)
