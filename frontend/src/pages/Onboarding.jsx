import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '../components/Button';

const slides = [
  {
    icon: 'receipt_long',
    title: 'Store all your receipts safely',
    description: 'Keep all your purchase records in one secure place for easy access anytime, anywhere.',
  },
  {
    icon: 'warranty',
    title: 'Track warranties automatically',
    description: 'Never lose track of warranty periods. We automatically calculate and monitor coverage.',
  },
  {
    icon: 'notifications_active',
    title: 'Never miss expiry reminders',
    description: 'Get timely alerts before warranties expire so you can take action when needed.',
  },
];

export function Onboarding() {
  const navigate = useNavigate();
  const [currentSlide, setCurrentSlide] = useState(0);
  
  const handleNext = () => {
    if (currentSlide < slides.length - 1) {
      setCurrentSlide(currentSlide + 1);
    } else {
      navigate('/login');
    }
  };
  
  const handleSkip = () => {
    navigate('/login');
  };
  
  return (
    <div className="min-h-screen bg-background-light dark:bg-background-dark flex flex-col">
      {/* Skip button */}
      <div className="flex justify-end p-6">
        <button 
          onClick={handleSkip}
          className="text-primary font-bold hover:opacity-80 transition-opacity"
        >
          Skip
        </button>
      </div>
      
      {/* Main content */}
      <div className="flex-1 flex flex-col items-center justify-center px-6">
        {/* Illustration */}
        <div className="w-full max-w-[480px] aspect-square rounded-xl bg-primary/10 dark:bg-primary/20 flex items-center justify-center mb-8 relative overflow-hidden">
          <span className="material-symbols-outlined text-primary text-[120px]">
            {slides[currentSlide].icon}
          </span>
          
          {/* Decorative elements */}
          <div className="absolute top-10 right-10 size-12 rounded-lg bg-primary/20 flex items-center justify-center">
            <span className="material-symbols-outlined text-primary">verified</span>
          </div>
          <div className="absolute bottom-10 left-10 size-16 rounded-full bg-primary/15 flex items-center justify-center">
            <span className="material-symbols-outlined text-primary">security</span>
          </div>
        </div>
        
        {/* Text content */}
        <div className="text-center space-y-4 max-w-md">
          <h1 className="text-3xl font-bold text-slate-900 dark:text-slate-100">
            {slides[currentSlide].title}
          </h1>
          <p className="text-lg text-slate-600 dark:text-slate-400">
            {slides[currentSlide].description}
          </p>
        </div>
        
        {/* Slide indicators */}
        <div className="flex gap-3 py-10">
          {slides.map((_, index) => (
            <div
              key={index}
              className={`h-2.5 rounded-full transition-all ${
                index === currentSlide 
                  ? 'w-8 bg-primary' 
                  : 'w-2.5 bg-slate-300 dark:bg-slate-700'
              }`}
            />
          ))}
        </div>
      </div>
      
      {/* Footer action */}
      <div className="p-6 pb-12 w-full max-w-[480px] mx-auto">
        <Button 
          onClick={handleNext}
          className="w-full py-4 rounded-xl text-lg shadow-lg"
        >
          {currentSlide === slides.length - 1 ? 'Get Started' : 'Next'}
        </Button>
      </div>
    </div>
  );
}
