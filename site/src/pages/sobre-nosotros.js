import React from 'react';
import Layout from '@theme/Layout';
import styles from './about.module.css';

export default function About() {
  return (
    <Layout title="Sobre nosotros" description="Equipo de DKY Labs - IA y Gestión de Datos">
      <main className="container margin-vert--lg">
        <h1>Sobre nosotros</h1>
        <p>
          <strong>DKY Labs</strong> es una empresa especializada en soluciones de <strong>Inteligencia Artificial</strong> y <strong>Gestión de Datos</strong>,
          enfocada en generar valor a partir del conocimiento organizacional. Combinamos experiencia técnica con una visión estratégica
          para acompañar a organizaciones en sus procesos de transformación digital.
        </p>

        <p>
          Nuestra labor abarca desde la implementación de <strong>programas de Gobierno del Dato (basados en DMBOK)</strong> y el uso de <strong>OpenMetadata</strong>,
          hasta el desarrollo de <strong>dashboards operativos, KPIs</strong> y <strong>asistentes inteligentes con RAG (Retrieval-Augmented Generation)</strong>.
        </p>

        <p>
          Nos caracteriza una metodología ágil, basada en <strong>sprints cortos y entregables medibles</strong>, orientada a resultados concretos y de impacto.
        </p>

        <h2>Equipo</h2>

        <div className="row margin-top--md">
          <div className="col col--6 text--center">
            <img
              src="/img/roberto.jpeg"
              alt="Roberto Villar"
              className={styles.profileImage}
            />
            <h3>Roberto Villar</h3>
            <p><em>CEO & Lead Data Consultant</em></p>
            <p>
              Especialista en gobernanza de datos, BI e inteligencia artificial aplicada.  
              Miembro activo de <a 
                href="https://www.damauruguay.org/quienes-somos/" 
                target="_blank" 
                rel="noopener noreferrer"
              >
                DAMA Uruguay
              </a>, capítulo local de la asociación internacional de gestión de datos (DAMA International).
            </p>
          </div>

          <div className="col col--6 text--center">
            <img
              src="/img/joana.jpeg"
              alt="Joana Aldorasi"
              className={styles.profileImage}
            />
            <h3>Joana Aldorasi</h3>
            <p><em>Subdirectora & Project Coordinator</em></p>
            <p>Enfocada en la gestión de proyectos y la coordinación operativa de soluciones tecnológicas.</p>
          </div>
        </div>

        <div className="text--center margin-top--lg">
          <p>📅 ¿Querés conversar con nosotros?</p>
          <a
            href="https://calendly.com/robertovillar18/30min/"
            className="button button--primary button--lg"
            target="_blank"
            rel="noopener noreferrer"
          >
            Agendá una reunión de 30 minutos
          </a>
        </div>
      </main>
    </Layout>
  );
}

