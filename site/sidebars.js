/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  guiaSidebar: [
    'intro',
    {
      type: 'category',
      label: 'Gestión de Datos',
      collapsed: false,
      items: [
        'gestion-datos/marco-teorico',
        'gestion-datos/como-llevar-a-la-practica',
      ],
    },
    {
      type: 'category',
      label: 'Inteligencia Artificial',
      collapsed: false,
      items: [
        'inteligencia-artificial/modelos-generativos',
        'inteligencia-artificial/aprendizaje-de-maquina',
        'inteligencia-artificial/como-implementar',
      ],
    },
  ],
};
export default sidebars;