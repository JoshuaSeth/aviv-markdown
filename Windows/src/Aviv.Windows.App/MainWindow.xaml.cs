using System.ComponentModel;
using Aviv.Windows.App.Services;
using Aviv.Windows.App.ViewModels;
using Microsoft.UI.Xaml;

namespace Aviv.Windows.App;

public sealed partial class MainWindow : Window
{
    private readonly EditorDocumentViewModel viewModel;
    private bool syncingFromViewModel;

    public MainWindow()
    {
        InitializeComponent();

        viewModel = new EditorDocumentViewModel(new MarkdownFileService(this));
        Content.DataContext = viewModel;
        EditorView.LoadMarkdown(viewModel.Markdown);

        viewModel.PropertyChanged += OnViewModelPropertyChanged;
        viewModel.EditRequested += action => EditorView.ApplyEditAction(action);
        viewModel.EditorCommandRequested += command => EditorView.PerformEditorCommand(command);
        viewModel.ViewScaleChanged += scale => EditorView.SetViewScale(scale);
        EditorView.MarkdownChanged += markdown =>
        {
            if (syncingFromViewModel)
            {
                return;
            }

            viewModel.UpdateFromEditor(markdown);
        };
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName != nameof(EditorDocumentViewModel.Markdown) || EditorView.Markdown == viewModel.Markdown)
        {
            return;
        }

        syncingFromViewModel = true;
        EditorView.LoadMarkdown(viewModel.Markdown);
        syncingFromViewModel = false;
    }
}
