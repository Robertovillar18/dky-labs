import React from 'react';
import Layout from '@theme/Layout';
import Link from '@docusaurus/Link';

export default function Home() {
  return (
    <Layout
      title="DKY Labs — Metadatos, BI e IA"
      description="Hacemos que tus datos trabajen hoy: metadatos, BI y asistentes IA listos en semanas."
    >
	<header className="hero hero--custom" style={{textAlign: 'center'}}>
	  <div className="container">
		<h1 className="hero__title" style={{marginBottom: '0.5rem'}}>
		  Hacemos que tus datos trabajen hoy
		</h1>
		<p className="hero__subtitle" style={{marginBottom: '1.5rem'}}>
		  Metadatos, BI y asistentes IA listos en semanas — no en trimestres.
		</p>
		<div style={{display: 'flex', gap: '12px', justifyContent: 'center'}}>
		  <Link className="button button--secondary button--lg" to="/servicios">
			Ver servicios
		  </Link>
		  <Link className="button button--lg" to="/contacto">
			Agendar llamada
		  </Link>
		</div>
	  </div>
	</header>

      <main>
        <section className="container margin-vert--lg">
          <div className="row">
            <div className="col col--4">
              <h3>Metadatos & Gobierno</h3>
              <p>Inventario, taxonomías y calidad de datos con enfoque DMBOK y OpenMetadata.</p>
            </div>
            <div className="col col--4">
              <h3>BI Exprés</h3>
              <p>KPIs críticos y dashboard operativo en semanas, con backlog de mejoras.</p>
            </div>
            <div className="col col--4">
              <h3>Asistentes IA / RAG</h3>
              <p>Respuestas confiables basadas en tus propios documentos y políticas.</p>
            </div>
          </div>
        </section>
      </main>
    </Layout>
  );
}
