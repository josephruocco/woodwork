import random

from calibre.gui2 import error_dialog
from calibre.gui2.actions import InterfaceAction
from qt.core import QAction, QMenu


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
        self.shelf_size = 60
        self.candidate_ids = None
        self.previous_search = ''
        self.plugin_search = ''

        self.qaction.triggered.connect(self.reshuffle)

        menu = QMenu(self.gui)
        menu.addAction(self._menu_action('Reshuffle Shelf', self.reshuffle))

        size_menu = menu.addMenu('Shelf Size')
        for size in (24, 36, 60, 90):
            size_menu.addAction(
                self._menu_action(
                    f'{size} books',
                    lambda checked=False, count=size: self.set_size(count),
                )
            )

        menu.addSeparator()
        menu.addAction(self._menu_action('Restore Previous View', self.restore_view))
        self.qaction.setMenu(menu)

    def _menu_action(self, title, callback):
        action = QAction(title, self.gui)
        action.triggered.connect(callback)
        return action

    def set_size(self, count):
        self.shelf_size = count
        self.reshuffle()

    def reshuffle(self, checked=False):
        model = self.gui.library_view.model()
        current_search = str(self.gui.search.current_text or '').strip()

        # Capture the user's current view only when entering WoodWork mode.
        # Subsequent reshuffles draw from the same pool instead of repeatedly
        # shrinking the last random subset.
        if self.candidate_ids is None or current_search != self.plugin_search:
            self.previous_search = current_search
            self.candidate_ids = list(model.all_current_book_ids())

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
        self.gui.search.set_search_string(previous, store_in_history=False)
        self.gui.status_bar.show_message('Restored your previous calibre view.', 4000)

    def library_changed(self, db):
        self.candidate_ids = None
        self.previous_search = ''
        self.plugin_search = ''

