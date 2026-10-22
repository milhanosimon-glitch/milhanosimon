#include <fcntl.h>
#include <unistd.h>

#define BUF_SIZE 4096

void	ft_puterr(char *str)
{
	int	len;

	len = 0;
	while (str[len])
		len++;
	write(2, str, len);
}

int	ft_display(char *path)
{
	int		fd;
	int		ret;
	char	buf[BUF_SIZE];

	fd = open(path, O_RDONLY);
	if (fd < 0)
		return (1);
	ret = read(fd, buf, BUF_SIZE);
	while (ret > 0)
	{
		write(1, buf, ret);
		ret = read(fd, buf, BUF_SIZE);
	}
	close(fd);
	if (ret < 0)
		return (1);
	return (0);
}

int	main(int argc, char **argv)
{
	if (argc < 2)
		ft_puterr("File name missing.\n");
	else if (argc > 2)
		ft_puterr("Too many arguments.\n");
	else if (ft_display(argv[1]))
		ft_puterr("Cannot read file.\n");
	else
		return (0);
	return (1);
}
