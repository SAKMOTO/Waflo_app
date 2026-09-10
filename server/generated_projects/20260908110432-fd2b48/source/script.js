```javascript
document.addEventListener('DOMContentLoaded', () => {
    const coffeeCardsContainer = document.querySelector('.coffee-cards');
    const filterButtons = document.querySelectorAll('.filter-bar button');
    const coffeeWeightSlider = document.getElementById('coffee-weight');
    const waterAmountDisplay = document.getElementById('water-amount');
    const methodTabs = document.querySelectorAll('.method-tabs button');
    const reservationForm = document.querySelector('.reservation-form form');
    const confirmationMessage = document.querySelector('.confirmation-message');
    const sampleBoxDrawer = document.querySelector('.sample-box-drawer');
    const sampleBoxBtn = document.querySelector('.sample-box-btn');
    const closeBtn = document.querySelector('.close-btn');

    // Sample coffee beans dataset
    const coffeeBeans = [
        {
            name: 'Ethiopian Yirgacheffe',
            origin: 'Ethiopia',
            region: 'Yirgacheffe',
            elevation: 2000,
            process: 'Washed',
            tastingNotes: ['Citrus', 'Floral', 'Berry'],
            roastScore: 3,
            size: '250g',
            price: 15.99
        },
        {
            name: 'Colombian Supremo',
            origin: 'Colombia',
            region: 'Huila',
            elevation: 1800,
            process: 'Natural',
            tastingNotes: ['Nutty', 'Chocolate', 'Fruit'],
            roastScore: 4,
            size: '500g',
            price: 19.99
        },
        // Add more coffee beans here
    ];

    // Sample brew guide profiles
    const brewGuideProfiles = {
        'pour-over': { ratio: 16, grind: 'Medium', time: '3-4 minutes', steps: ['Preheat your kettle', 'Grind your coffee beans', 'Add coffee to the filter', 'Pour water over the coffee'] },
        'french-press': { ratio: 14, grind: 'Coarse', time: '4 minutes', steps: ['Add coffee to the press', 'Pour hot water over the coffee', 'Stir and place the plunger on top', 'Press the plunger down'] },
        'aeropress': { ratio: 15, grind: 'Fine', time: '1.5 minutes', steps: ['Add coffee to the chamber', 'Pour hot water over the coffee', 'Stir and place the plunger on top', 'Press the plunger down'] }
    };

    // Function to generate coffee card HTML
    function generateCoffeeCard(coffee) {
        return `
            <div class="coffee-card" data-roast="${coffee.roastScore}">
                <img src="https://via.placeholder.com/200" alt="${coffee.name}">
                <div class="origin-flag"></div>
                <h4>${coffee.name}</h4>
                <div class="roast-meter">
                    ${Array.from({ length: 5 }, (_, i) => `<div class="flame" style="color: ${i < coffee.roastScore ? '#C87D55' : '#2A1B17'}"></div>`).join('')}
                </div>
                <div class="flavor-tags">${coffee.tastingNotes.join(', ')}</div>
                <p class="price">$${coffee.price}</p>
                <button class="add-btn">Add to Sample Box</button>
            </div>
        `;
    }

    // Function to filter and display coffee cards
    function displayCoffeeCards(filter) {
        let filteredBeans = coffeeBeans;
        if (filter !== 'all') {
            if (filter === 'single-origin') {
                filteredBeans = filteredBeans.filter(bean => bean.name.includes('Single Origin'));
            } else if (filter === 'espresso') {
                filteredBeans = filteredBeans.filter(bean => bean.name.includes('Espresso'));
            } else {
                filteredBeans = filteredBeans.filter(bean => bean.roastScore === parseInt(filter));
            }
        }
        coffeeCardsContainer.innerHTML = filteredBeans.map(generateCoffeeCard).join('');
    }

    // Event listener for filter buttons
    filterButtons.forEach(button => {
        button.addEventListener('click', (e) => {
            filterButtons.forEach(btn => btn.classList.remove('active'));
            e.target.classList.add('active');
            displayCoffeeCards(e.target.dataset.filter);
        });
    });

    // Event listener for coffee weight slider
    coffeeWeightSlider.addEventListener('input', () => {
        const coffeeWeight = coffeeWeightSlider.value;
        coffeeWeightSlider.nextElementSibling.textContent = `${coffeeWeight}g`;
        const selectedMethod = document.querySelector('.method-tabs button.active').dataset.method;
        const waterAmount = coffeeWeight * brewGuideProfiles[selectedMethod].ratio;
        waterAmountDisplay.textContent = `${waterAmount}g`;
    });

    // Event listener for brew method tabs
    methodTabs.forEach(tab => {
        tab.addEventListener('click', (e) => {
            methodTabs.forEach(t => t.classList.remove('active'));
            e.target.classList.add('active');
            const selectedMethod = e.target.dataset.method;
            const waterAmount = coffeeWeightSlider.value * brewGuideProfiles[selectedMethod].ratio;
            waterAmountDisplay.textContent = `${waterAmount}g`;
            document.querySelector('.grind-size p').textContent = `Grind Size: ${brewGuideProfiles[selectedMethod].grind}`;
            document.querySelector('.brew-steps ul').innerHTML = brewGuideProfiles[selectedMethod].steps.map(step => `<li>${step}</li>`).join('');
        });
    });

    // Event listener for reservation form
    reservationForm.addEventListener('submit', (e) => {
        e.preventDefault();
        const attendees = document.getElementById('attendees').value;
        const date = document.getElementById('date').value;
        confirmationMessage.textContent = `Your reservation for ${attendees} attendees on ${date} has been confirmed!`;
        confirmationMessage.style.display = 'block';
    });

    // Event listener for sample box button
    sampleBoxBtn.addEventListener('click', () => {
        sampleBoxDrawer.classList.add('active');
    });

    // Event listener for close button
    closeBtn.addEventListener('click', () => {
        sampleBoxDrawer.classList.remove('active');
    });

    // Initial display of coffee cards
    displayCoffeeCards('all');

    // Initial setup for brew guide
    const initialMethod = 'pour-over';
    methodTabs[0].classList.add('active');
    coffeeWeightSlider.dispatchEvent(new Event('input'));
});
```