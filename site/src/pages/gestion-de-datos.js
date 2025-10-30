import React from 'react';
import Layout from '@theme/Layout';
import Link from '@docusaurus/Link';

export default function GestionDeDatos() {
  return (
    <Layout
      title="Cómo llevar a la práctica la Gestión de Datos"
      description="De la teoría a la operación: metadatos, datos maestros y OpenMetadata para generar valor en semanas."
    >
      <main className="container margin-vert--lg">
        {/* Intro */}
        <section>
          <h1>Cómo llevar a la práctica la Gestión de Datos</h1>
          <p style={{maxWidth: 920}}>
            La mayoría de las organizaciones se frena por intentar abarcar todo al inicio. La forma correcta es
            <strong> empezar simple</strong> y con foco: <strong>metadatos</strong> + definición de
            <strong> datos maestros</strong> y <strong>transaccionales</strong>, apoyados por una herramienta
            abierta y madura como <strong>OpenMetadata</strong>. Desde ahí habilitamos calidad, linaje y
            analítica confiable.
          </p>
          <div style={{marginTop: 16}}>
            <Link className="button button--primary button--lg" to="/contacto">
              Agendar una reunión
            </Link>
          </div>
        </section>

        {/* Arquitectura */}
        <section className="margin-top--xl">
          <h2>Arquitectura de referencia</h2>
          <p style={{maxWidth: 920}}>
            Un modelo por capas que conecta fuentes, metadatos y gobierno con los consumidores de datos (BI, IA,
            APIs). Simple de entender, fácil de escalar.
          </p>
          <img
            src="/img/arquitectura-gestion-datos.png"
            alt="Arquitectura de Gestión de Datos por capas con OpenMetadata"
            style={{width: '100%', borderRadius: 12, boxShadow: '0 6px 24px rgba(0,0,0,.08)'}}
          />
        </section>

        {/* Definiciones clave */}
        <section className="margin-top--xl">
          <h2>Dos definiciones que ordenan todo</h2>
          <div className="row">
            <div className="col col--6">
              <div style={{background:'#f5f7fa', borderRadius:12, padding:'1.25rem'}}>
                <h3 style={{marginTop:0}}>Datos Maestros</h3>
                <p style={{marginBottom:0}}>
                  Entidades estables del negocio (p. ej., <em>Persona, Trámite, Producto</em>). Se gobiernan con
                  <strong> metadatos</strong>, responsables y reglas claras. Son el punto de partida.
                </p>
              </div>
            </div>
            <div className="col col--6">
              <div style={{background:'#f5f7fa', borderRadius:12, padding:'1.25rem'}}>
                <h3 style={{marginTop:0}}>Datos Transaccionales</h3>
                <p style={{marginBottom:0}}>
                  Registros de eventos/operaciones (p. ej., <em>Solicitudes, Pagos, Inscripciones</em>). Se
                  conectan a maestros y alimentan analítica y tableros.
                </p>
              </div>
            </div>
          </div>
        </section>

        {/* Linaje */}
        <section className="margin-top--xl">
          <h2>Linaje de datos (de dónde viene cada dato)</h2>
          <p style={{maxWidth: 920}}>
            OpenMetadata traza automáticamente el recorrido de los datos entre orígenes, procesos y
            visualizaciones. Esto habilita auditoría, impacto de cambios y confianza.
          </p>
          <img
            src="/img/linaje-de-datos.png"
            alt="Diagrama de linaje de datos con OpenMetadata"
            style={{width: '100%', borderRadius: 12, boxShadow: '0 6px 24px rgba(0,0,0,.08)'}}
          />
        </section>

        {/* Calidad */}
        <section className="margin-top--xl">
          <h2>Calidad de datos automatizada</h2>
          <p style={{maxWidth: 920}}>
            Definimos pruebas sobre columnas y tablas (unicidad, nulos, dominios válidos, integridad) y monitoreamos
            resultados con alertas. La calidad deja de ser algo manual.
          </p>
          <img
            src="/img/calidad-de-datos.png"
            alt="Panel de calidad de datos: unicidad, nulos, integridad y métricas"
            style={{width: '100%', maxWidth: 920, borderRadius: 12, boxShadow: '0 6px 24px rgba(0,0,0,.08)'}}
          />
        </section>

        {/* Roadmap */}
        <section className="margin-top--xl">
          <h2>Roadmap en 4 etapas (2–8 semanas)</h2>
          <div className="row">
            <div className="col col--3">
              <div style={{background:'#eef4ff', borderRadius:10, padding:'1rem', height:'100%'}}>
                <strong>1. Datos Maestros</strong>
                <ul>
                  <li>Inventario y definiciones</li>
                  <li>Propietarios y políticas</li>
                </ul>
              </div>
            </div>
            <div className="col col--3">
              <div style={{background:'#eef4ff', borderRadius:10, padding:'1rem', height:'100%'}}>
                <strong>2. OpenMetadata</strong>
                <ul>
                  <li>Catálogo y dominios</li>
                  <li>Conectores a fuentes</li>
                </ul>
              </div>
            </div>
            <div className="col col--3">
              <div style={{background:'#eef4ff', borderRadius:10, padding:'1rem', height:'100%'}}>
                <strong>3. Calidad & Linaje</strong>
                <ul>
                  <li>Pruebas y alertas</li>
                  <li>Impacto de cambios</li>
                </ul>
              </div>
            </div>
            <div className="col col--3">
              <div style={{background:'#eef4ff', borderRadius:10, padding:'1rem', height:'100%'}}>
                <strong>4. Analítica & IA</strong>
                <ul>
                  <li>Dashboards confiables</li>
                  <li>RAG / modelos con trazas</li>
                </ul>
              </div>
            </div>
          </div>

          <img
            src="/img/roadmap-4-etapas.png"
            alt="Roadmap de implementación en cuatro etapas"
            style={{width: '100%', maxWidth: 920, borderRadius: 12, boxShadow: '0 6px 24px rgba(0,0,0,.08)', marginTop: 16}}
          />

          <div className="margin-top--lg" style={{textAlign:'center'}}>
            <Link className="button button--primary button--lg" to="/contacto">
              Quiero empezar por la Etapa 1
            </Link>
          </div>
        </section>

        {/* Resultados / CTA final */}
        <section className="margin-top--xl">
          <h2>Resultados visibles y medibles</h2>
          <p style={{maxWidth: 920}}>
            Inventario, dominios, linaje y calidad en un tablero ejecutivo. Priorizamos por impacto y esfuerzo para
            construir una hoja de ruta clara y realista.
          </p>
          <img
            src="/img/cuadro-mando-metadatos.png"
            alt="Cuadro de mando de metadatos y calidad"
            style={{width: '100%', borderRadius: 12, boxShadow: '0 6px 24px rgba(0,0,0,.08)'}}
          />
          <div className="margin-top--lg" style={{textAlign:'center'}}>
            <Link className="button button--secondary button--lg" to="/servicios">
              Ver paquetes y precios
            </Link>
          </div>
        </section>
      </main>
    </Layout>
  );
}

