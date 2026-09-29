// Shared sidebar for codyparham.com. The project list lives here only.
//
// To add a project: put its page in maps/<id>/index.html and add an entry
// with id, name (sidebar label), title, meta (one-line description) and src.
// An entry with only a name is shown as a "Soon" placeholder.
(function () {
    const PROJECTS = [
        {
            id: "montgomery-roads",
            name: "Clarksville, TN Driving Directions",
            title: "Interactive Montgomery County Roadways",
            meta: "Roads, driving directions and PostGIS routing for Clarksville, TN",
            src: "maps/montgomery-roads/"
        },
        { name: "Powerlines Storm Risk Assessment" },
        { name: "Clarksville, TN growth tracker" }
    ];

    const ICON_MAP = '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 6l6-3 6 3 6-3v15l-6 3-6-3-6 3z"/><path d="M9 3v15M15 6v15"/></svg>';
    const ICON_SOON = '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9" stroke-dasharray="3 3"/></svg>';

    // options.page: "about" (the home page, index.html) or "projects" (projects.html).
    // On the projects page, project links only change the hash, so the page doesn't reload.
    const renderSidebar = function (sidebar, options) {
        const projectsHref = options.page === "projects" ? "" : "projects.html";
        const live = PROJECTS.filter(function (project) {
            return project.src;
        });

        const items = PROJECTS.map(function (project) {
            if (!project.src) {
                return '<li><div class="project-soon" aria-disabled="true">' + ICON_SOON +
                    '<span class="project-name">' + project.name + '</span>' +
                    '<span class="soon-badge">Soon</span></div></li>';
            }
            return '<li><a class="project-link" href="' + projectsHref + '#/' + project.id + '">' + ICON_MAP +
                '<span class="project-name">' + project.name + '</span>' +
                '<span class="live-dot" aria-hidden="true"></span><span class="sr-only">(live)</span></a></li>';
        }).join("");

        sidebar.innerHTML =
            '<div class="brand">' +
                '<a class="brand-mark" href="./" aria-label="Home">CP</a>' +
                '<div class="brand-text">' +
                    '<span class="brand-name">Cody Parham</span>' +
                    '<a class="connect-link" href="./"' +
                        (options.page === "about" ? ' aria-current="page"' : '') +
                        '>Click here to connect with me!</a>' +
                '</div>' +
            '</div>' +
            '<nav class="nav" aria-label="Projects">' +
                '<p class="nav-label">Projects</p>' +
                '<ul class="project-list">' + items + '</ul>' +
            '</nav>' +
            '<div class="sidebar-footer">' +
                '<p class="progress-label">Projects live</p>' +
                '<p class="progress-value">' + live.length + ' of ' + PROJECTS.length + '</p>' +
                '<div class="progress" aria-hidden="true"><span style="width: ' +
                    (100 * live.length / PROJECTS.length) + '%"></span></div>' +
            '</div>';
    };

    window.Site = {
        projects: PROJECTS,
        renderSidebar: renderSidebar
    };
})();
