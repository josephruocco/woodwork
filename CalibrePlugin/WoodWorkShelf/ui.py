import random

from calibre.gui2 import error_dialog, info_dialog, open_url
from calibre.gui2.actions import InterfaceAction
from calibre.utils.config import JSONConfig
from qt.core import QAction, QMenu, QUrl


prefs = JSONConfig('plugins/woodwork_shelf')
prefs.defaults['shelf_size'] = 60


class WoodWorkShelfAction(InterfaceAction):
    name = 'WoodWork Shelf'
    action_spec = (
        'Reshuffle Shelf',
        'images/icon.png',
        'Show a fresh random shelf from the current calibre view',
        'Ctrl+Shift+R',
    )
    action_type = 'current'

    def genesis(self):
        self.shelf_size = self._saved_shelf_size()
        self.candidate_ids = None
        self.previous_search = ''
        self.plugin_search = ''
        self.size_actions = {}

        self.qaction.triggered.connect(self.reshuffle)

        menu = QMenu(self.gui)
        menu.addAction(self._menu_action('Reshuffle Shelf', self.reshuffle))

        size_menu = menu.addMenu('Shelf Size')
        for size in (24, 36, 60, 90):
            action = self._menu_action(
                f'{size} books',
                lambda checked=False, count=size: self.set_size(count),
            )
            action.setCheckable(True)
            self.size_actions[size] = action
            size_menu.addAction(action)

        menu.addSeparator()
        self.restore_action = self._menu_action('Restore Previous View', self.restore_view)
        self.restore_action.setEnabled(False)
        menu.addAction(self.restore_action)
        menu.addSeparator()
        menu.addAction(self._menu_action('About WoodWork Shelf', self.show_about))
        menu.addAction(self._menu_action('WoodWork for iPhone', self.open_website))
        self.qaction.setMenu(menu)
        self._update_size_actions()

    def _menu_action(self, title, callback):
        action = QAction(title, self.gui)
        action.triggered.connect(callback)
        return action

    def set_size(self, count):
        self.shelf_size = count
        prefs['shelf_size'] = count
        self._update_size_actions()
        self.reshuffle()

    def _saved_shelf_size(self):
        try:
            value = int(prefs['shelf_size'])
        except (TypeError, ValueError):
            value = 60
        return value if value in (24, 36, 60, 90) else 60

    def _update_size_actions(self):
        for size, action in self.size_actions.items():
            action.setChecked(size == self.shelf_size)

    def reshuffle(self, checked=False):
        model = self.gui.library_view.model()
        current_search = str(self.gui.search.current_text or '').strip()

        # Capture the user's current view only when entering WoodWork mode.
        # Subsequent reshuffles draw from the same pool instead of repeatedly
        # shrinking the last random subset.
        if self.candidate_ids is None or current_search != self.plugin_search:
            self.previous_search = current_search
            self.candidate_ids = list(model.all_current_book_ids())
            self.restore_action.setEnabled(True)

        if not self.candidate_ids:
            error_dialog(
                self.gui,
                'WoodWork Shelf',
                'There are no books in the current view to reshuffle.',
                show=True,
            )
            return

        count = min(self.shelf_size, len(self.candidate_ids))
        selected = random.SystemRandom().sample(self.candidate_ids, count)
        self.plugin_search = ' or '.join(f'id:={book_id}' for book_id in selected)

        self.gui.search.set_search_string(self.plugin_search, store_in_history=False)
        self.gui.status_bar.show_message(
            f'WoodWork surfaced {count} of {len(self.candidate_ids)} books.',
            5000,
        )

    def restore_view(self, checked=False):
        if self.candidate_ids is None:
            return
        previous = self.previous_search
        self.candidate_ids = None
        self.previous_search = ''
        self.plugin_search = ''
        self.restore_action.setEnabled(False)
        self.gui.search.set_search_string(previous, store_in_history=False)
        self.gui.status_bar.show_message('Restored your previous calibre view.', 4000)

    def library_changed(self, db):
        self.candidate_ids = None
        self.previous_search = ''
        self.plugin_search = ''
        self.restore_action.setEnabled(False)

    def show_about(self, checked=False):
        info_dialog(
            self.gui,
            'WoodWork Shelf',
            'WoodWork Shelf 1.1.0\n\n'
            'Reshuffles the books in your current search or Virtual Library. '
            'It never changes book files or metadata.\n\n'
            'Use WoodWork for iPhone to put a rotating version of your library '
            'on your Home Screen.',
            show=True,
        )

    def open_website(self, checked=False):
        open_url(QUrl('https://getwoodwork.app/calibre/'))
