from calibre.customize import InterfaceActionBase


class WoodWorkShelfPlugin(InterfaceActionBase):
    name = 'WoodWork Shelf'
    description = 'Reshuffle the current calibre view into a rotating shelf of books.'
    supported_platforms = ['windows', 'osx', 'linux']
    author = 'Joseph Ruocco'
    version = (1, 1, 0)
    minimum_calibre_version = (7, 0, 0)
    actual_plugin = 'calibre_plugins.woodwork_shelf.ui:WoodWorkShelfAction'
