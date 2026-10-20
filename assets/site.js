// Project list and project windows for codyparham.com. The project list lives here only.
//
// To add a project: put its page in maps/<id>/index.html and add an entry
// with id, name (nav label), title, meta (one-line description) and src.
// An optional logo (image path) is shown in its window in place of the title.
// An entry with only a name is shown as a "Soon" placeholder.
(function () {
    const PROJECTS = [
        {
            id: "rexplorer",
            name: "RExplorer",
            logo: "assets/rexplorer-logo.png",
            title: "RExplorer: Commercial Property Explorer",
            meta: "Parcels, flood zones and site data for evaluating commercial property in Clarksville, TN",
            src: "https://rexplorer.codyparham.com/"
        },
        {
            id: "montgomery-roads",
            name: "Driving Directions",
            title: "Clarksville, TN Driving Directions",
            meta: "Roads, driving directions and PostGIS routing for Montgomery County, TN",
            src: "maps/montgomery-roads/"
        },
        { name: "Powerlines Storm Risk Assessment" },
        { name: "Clarksville, TN Growth Tracker" }
    ];

    const ICON_OPEN = '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg>';

    const live = PROJECTS.filter(function (project) {
        return project.src;
    });
    const soon = PROJECTS.filter(function (project) {
        return !project.src;
    });

    // One full-width window per live project, then the "Soon" placeholders.
    const renderProjects = function (container) {
        const windows = live.map(function (project, index) {
            const heading = project.logo
                ? '<img class="project-logo" src="' + project.logo + '" alt="' + project.name + '" width="132" height="30">' +
                    '<h3 class="sr-only">' + project.title + '</h3>'
                : '<h3>' + project.title + '</h3>';
            return '<section class="card project-window" id="' + project.id + '" aria-label="' + project.title + '">' +
                '<div class="card-head">' +
                    '<div class="project-title">' +
                        '<p class="eyebrow"><span class="live-dot" aria-hidden="true"></span>Project ' +
                            String(index + 1).padStart(2, "0") + '</p>' +
                        heading +
                        '<p>' + project.meta + '</p>' +
                    '</div>' +
                    '<a class="button" href="' + project.src + '" target="_blank" rel="noopener" aria-label="Open ' +
                        project.title + ' in a new tab"><span class="label-long">Open full page</span>' + ICON_OPEN + '</a>' +
                '</div>' +
                '<iframe src="' + project.src + '" title="' + project.title + '" loading="lazy" allowfullscreen></iframe>' +
            '</section>';
        }).join("");

        const placeholders = soon.length
            ? '<ul class="soon-list" aria-label="Coming soon">' + soon.map(function (project) {
                return '<li>' + project.name + '<span class="soon-badge">Soon</span></li>';
            }).join("") + '</ul>'
            : "";

        container.innerHTML = windows + placeholders;
    };

    // Nav links to each live project, after the static links already in the list.
    const renderNav = function (list) {
        list.insertAdjacentHTML("beforeend", live.map(function (project) {
            return '<li class="nav-optional"><a href="#' + project.id + '">' + project.name + '</a></li>';
        }).join(""));
    };

    // Highlight the nav link for the section in view.
    const trackSections = function (list) {
        const links = Array.from(list.querySelectorAll('a[href^="#"]'));
        const sections = links.map(function (link) {
            return document.getElementById(link.getAttribute("href").slice(1));
        }).filter(Boolean);
        const observer = new IntersectionObserver(function (entries) {
            entries.forEach(function (entry) {
                if (!entry.isIntersecting) {
                    return;
                }
                links.forEach(function (link) {
                    if (link.getAttribute("href") === "#" + entry.target.id) {
                        link.setAttribute("aria-current", "true");
                    } else {
                        link.removeAttribute("aria-current");
                    }
                });
            });
        }, { rootMargin: "-45% 0px -50% 0px" });
        sections.forEach(function (section) {
            observer.observe(section);
        });
    };

    window.Site = {
        projects: PROJECTS,
        renderProjects: renderProjects,
        renderNav: renderNav,
        trackSections: trackSections
    };
})();
