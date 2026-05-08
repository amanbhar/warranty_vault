import { useState } from 'react';
import { remindersAPI } from '../services/api';
import { Card } from './Card';
import { Button } from './Button';
import { Input } from './Input';
import { cn } from '../utils/cn';

export function RemindersSection({ itemId, reminders: initialReminders, expiryDate }) {
    const [reminders, setReminders] = useState(initialReminders || []);
    const [showAddForm, setShowAddForm] = useState(false);
    const [newRemindAt, setNewRemindAt] = useState('');
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(null);
    const [editingId, setEditingId] = useState(null);

    const handleAddCustom = async (date) => {
        setLoading(true);
        setError(null);
        try {
            if (editingId) {
                const response = await remindersAPI.update(itemId, editingId, { reminder: { remind_at: date } });
                setReminders(reminders.map(r => r.id === editingId ? response.data.reminder : r).sort((a, b) => new Date(a.remind_at) - new Date(b.remind_at)));
                setEditingId(null);
            } else {
                const response = await remindersAPI.create(itemId, { reminder: { remind_at: date } });
                setReminders([...reminders, response.data.reminder].sort((a, b) => new Date(a.remind_at) - new Date(b.remind_at)));
            }
            setShowAddForm(false);
            setNewRemindAt('');
        } catch (err) {
            setError(err.response?.data?.error || 'Failed to save reminder');
        } finally {
            setLoading(false);
        }
    };

    const handleDelete = async (id) => {
        if (!window.confirm('Remove this custom reminder?')) return;
        try {
            await remindersAPI.delete(itemId, id);
            setReminders(reminders.filter(r => r.id !== id));
        } catch (err) {
            alert('Failed to delete reminder');
        }
    };

    const handleEdit = (r) => {
        setEditingId(r.id);
        setNewRemindAt(r.remind_at.split('T')[0]);
        setShowAddForm(true);
    };

    const handleQuickAdd = (daysBefore) => {
        const date = new Date(expiryDate);
        date.setDate(date.getDate() - daysBefore);
        handleAddCustom(date.toISOString().split('T')[0]);
    };

    const formatDate = (dateStr) => {
        return new Date(dateStr).toLocaleDateString(undefined, {
            day: 'numeric',
            month: 'short',
            year: 'numeric'
        });
    };

    return (
        <div className="mt-8">
            <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-bold text-slate-900 dark:text-slate-100">Reminders</h3>
                {!showAddForm && (
                    <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => setShowAddForm(true)}
                        className="text-primary hover:bg-primary/10"
                    >
                        <span className="material-symbols-outlined mr-1 text-sm">add</span>
                        Add Custom
                    </Button>
                )}
            </div>

            {showAddForm && (
                <Card className="p-4 mb-4 border-primary/30 bg-primary/5 animate-in fade-in slide-in-from-top-2">
                    <p className="text-xs font-bold text-primary uppercase tracking-widest mb-3">
                        {editingId ? 'Edit Reminder' : 'Add Custom Reminder'}
                    </p>
                    {!editingId && (
                        <div className="flex flex-wrap gap-2 mb-4">
                            <button
                                onClick={() => handleQuickAdd(15)}
                                className="px-3 py-1.5 rounded-full text-xs font-bold bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 text-slate-600 dark:text-slate-300 hover:border-primary hover:text-primary transition-all"
                            >
                                15 Days Before
                            </button>
                            <button
                                onClick={() => handleQuickAdd(3)}
                                className="px-3 py-1.5 rounded-full text-xs font-bold bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 text-slate-600 dark:text-slate-300 hover:border-primary hover:text-primary transition-all"
                            >
                                3 Days Before
                            </button>
                        </div>
                    )}

                    <div className="flex gap-2">
                        <Input
                            type="date"
                            value={newRemindAt}
                            onChange={(e) => setNewRemindAt(e.target.value)}
                            className="flex-1"
                            error={error}
                            max={expiryDate}
                        />
                        <Button
                            onClick={() => handleAddCustom(newRemindAt)}
                            disabled={!newRemindAt || loading}
                            className="h-[46px]"
                        >
                            {loading ? '...' : (editingId ? 'Save' : 'Add')}
                        </Button>
                        <Button
                            variant="outline"
                            onClick={() => { setShowAddForm(false); setEditingId(null); setNewRemindAt(''); }}
                            className="h-[46px]"
                        >
                            Cancel
                        </Button>
                    </div>
                </Card>
            )}

            <div className="space-y-3">
                {reminders.length > 0 ? (
                    reminders.map((r) => (
                        <div
                            key={r.id}
                            className={cn(
                                "flex items-center justify-between p-4 rounded-2xl border transition-all",
                                r.reminder_type === 'default'
                                    ? "bg-slate-50 dark:bg-slate-800/50 border-slate-100 dark:border-slate-800"
                                    : "bg-white dark:bg-slate-900 border-primary/10 hover:border-primary/30 shadow-sm"
                            )}
                        >
                            <div className="flex items-center gap-3">
                                <div className={cn(
                                    "size-10 rounded-xl flex items-center justify-center",
                                    r.sent
                                        ? "bg-slate-200 text-slate-400"
                                        : r.reminder_type === 'default' ? "bg-slate-100 text-slate-500" : "bg-primary/10 text-primary"
                                )}>
                                    <span className="material-symbols-outlined text-xl">
                                        {r.sent ? 'notifications_off' : 'notifications_active'}
                                    </span>
                                </div>
                                <div>
                                    <div className="flex items-center gap-2">
                                        <p className="text-sm font-bold text-slate-900 dark:text-slate-100">
                                            {formatDate(r.remind_at)}
                                        </p>
                                        {r.reminder_type === 'default' && (
                                            <span className="text-[10px] bg-slate-200 dark:bg-slate-700 text-slate-600 dark:text-slate-400 px-1.5 py-0.5 rounded font-black uppercase tracking-tight">
                                                Default
                                            </span>
                                        )}
                                    </div>
                                    <p className="text-xs text-slate-500 font-medium">
                                        {r.sent ? 'Already sent' : 'Upcoming notification'}
                                    </p>
                                </div>
                            </div>

                            {r.reminder_type === 'custom' && !r.sent && (
                                <div className="flex items-center gap-2">
                                    <button
                                        onClick={() => handleEdit(r)}
                                        className="size-8 rounded-lg flex items-center justify-center text-slate-400 hover:text-primary hover:bg-primary/5 transition-all"
                                    >
                                        <span className="material-symbols-outlined text-lg">edit</span>
                                    </button>
                                    <button
                                        onClick={() => handleDelete(r.id)}
                                        className="size-8 rounded-lg flex items-center justify-center text-slate-400 hover:text-rose-500 hover:bg-rose-50 dark:hover:bg-rose-950/20 transition-all"
                                    >
                                        <span className="material-symbols-outlined text-lg">delete</span>
                                    </button>
                                </div>
                            )}
                        </div>
                    ))
                ) : (
                    <div className="py-8 text-center text-slate-400 border-2 border-dashed border-slate-100 dark:border-slate-800 rounded-3xl">
                        <span className="material-symbols-outlined text-4xl mb-2">notifications_none</span>
                        <p className="text-sm">No reminders set for this item</p>
                    </div>
                )}
            </div>
        </div>
    );
}
