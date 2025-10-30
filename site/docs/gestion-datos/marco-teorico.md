---
id: marco-teorico
title: Marco teórico
---

## ¿Qué es la Gestión de Datos?
Conjunto de capacidades para **gobernar, definir, catalogar, asegurar y medir** los datos a lo largo de su ciclo de vida (DMBOK).

---

## ¿Por qué fallan tantos proyectos de datos?

- **Silos y falta de contexto.** No hay catálogo ni trazabilidad, nadie confía en los números.  
- **Intentar empezar por todo.** Sin priorizar datos maestros y metadatos, nada ordena.  
- **Herramientas inadecuadas.** Excel no escala. OpenMetadata automatiza catálogo, linaje y calidad.

---

## Puntos clave
- **Metadatos** como punto de partida.
- **Datos maestros** (entidades estables) vs **datos transaccionales** (eventos).
- **Dominios** de negocio y responsables (accountability).

---

## El modelo que funciona

1. **Identificar datos maestros** (p. ej., Persona, Trámite, Producto).  
2. **Implementar OpenMetadata** (catálogo, dominios, ownership).  
3. **Activar Calidad & Linaje** (pruebas y dependencias visibles).  
4. **Analítica & IA confiable** (dashboards, RAG, evaluación).

---

## Arquitectura

![Arquitectura](/img/arquitectura-gestion-datos.png)

---

## Linaje de datos

OpenMetadata muestra de dónde viene cada dato y a quién impacta un cambio.

![Linaje](/img/linaje-de-datos.png)

---

## Calidad de datos automatizada

Pruebas sobre columnas/tablas (unicidad, nulos, integridad) + alertas y métricas.

![Calidad](/img/calidad-de-datos.png)

---

## Roadmap en 4 etapas (2–8 semanas)

![Roadmap](/img/roadmap-4-etapas.png)

<div style={{textAlign:'center', marginTop: 16}}>
  <Link className="button button--primary button--lg" to="/contacto">Quiero empezar por la Etapa 1</Link>
</div>