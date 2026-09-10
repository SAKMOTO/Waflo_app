```javascript
document.addEventListener('DOMContentLoaded', function() {
    // Smooth scrolling for navigation links
    document.querySelectorAll('nav a').forEach(anchor => {
        anchor.addEventListener('click', function(e) {
            e.preventDefault();
            document.querySelector(this.getAttribute('href')).scrollIntoView({
                behavior: 'smooth'
            });
        });
    });

    // Form validation and success message
    const form = document.getElementById('contact-form');
    const successMessage = document.getElementById('success-message');

    form.addEventListener('submit', function(e) {
        e.preventDefault();
        const email = document.getElementById('email');
        const message = document.getElementById('message');

        if (email.checkValidity() && message.checkValidity()) {
            successMessage.classList.remove('hidden');
            form.reset();
        } else {
            alert('Please fill out all required fields correctly.');
        }
    });

    // Project cards fade-in on scroll
    const projectCards = document.querySelectorAll('.project-card');
    const options = {
        rootMargin: '0px',
        threshold: 0.1
    };

    const observer = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.setAttribute('data-scroll', 'fadeIn');
                observer.unobserve(entry.target);
            }
        });
    }, options);

    projectCards.forEach(card => {
        observer.observe(card);
    });
});
```