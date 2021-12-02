#!/bin/bash

numeroJoueur=$1			#numéro du joueur passe en paramètre dans le gestionnaire du jeu
partieFini=false		#boolean pour savoir si la partie est finie
topDepart=false			#boolean pour lancer la partie
cartesJoueur=()			#les cartes que le joueur possède
carteCourante=0			#la carte jouée par le joueur

echo Vous êtes le joueur de numero : $numeroJoueur

echo Entrez votre Nom :
read nomJoueur

echo Entrez votre Prenom :
read prenomJoueur

#méthode qui attend l'envoi des cartes du gestionnaire du jeu et qui les récupères.
waitCartes()
{
	onAttend=true
	#on boucle tant que l'on n'a pas pu se connecter au gestionnaire du jeu
	while [ $onAttend == "true" ]
	do	
		#permets la connexion au socket ouvert sur le processus du gestionnaire du jeu, et envoie que le joueur a reçu ses cartes
		echo "Joueur $numeroJoueur a recu ses cartes." | nc localhost 9091 2> /dev/null | echo "Vous avez reçu vos cartes" & onAttend=false
	done
	
	#on boucle sur me nombre d'élément dans le fichier
	for i in $(eval echo {1..$(wc -w tmp/cartePartie | cut -d" " -f1)}); 
	do	
		#on récupère dans le tableau des cartes du joueur, les cartes stockées sur le fichier tmp/cartePartie
		cartesJoueur+=($(echo $(cat tmp/cartePartie) | cut -d" " -f$i))	
	done
	echo "" > tmp/cartePartie
}

#méthode qui attend le top départ.
waitTopDepart()
{
	#socket ouvert en lecture qui attente le top départ envoyé par le gestionnaire du jeu
	echo "Joueur $numeroJoueur a recu le top depart." | nc -l -p 9092 | echo "Attente du top départ."
}

#méthode qui retire la carte passée en paramètre du tableau des cartes.
retireCarte()
{
	carteRetirer=$1		 #indice de la carte a retirer 
	cartesTemp=()		 #tableau temporaire 
	
	#on vide le tableau de tout son contenue avant de le remplir
	unset cartesTemp 
	
	#on copie les cartes du joueur
	cartesTemp=("${cartesJoueur[@]}")
	
	#on vide le tableau de tout son contenue avant de le remplir
	unset cartesJoueur
	
	#récupération des bonnes valeur c'est-à-dire toutes sauf la carte retirer
	for i in $(eval echo {0..$((${#cartesTemp[*]} - 1))});
	do	
		if (( "$carteRetirer" != ${cartesTemp[$i]} ));
		then
			cartesJoueur+=(${cartesTemp[$i]})	
		fi
	done
}

#méthode qui vérifie si la partie est terminée.
finGame()
{
	#vérifie si la première ligne du fichier tmp/finGame est égal à la chaine de caractère "fin"
	if [ "$(echo $(cat tmp/finGame) | cut -d" " -f1)" == "fin" ];
	then
		#on écrit dans le terminal l'erreur contenue dans le fichier tmp/finGame
		tail -n 1 tmp/finGame
		partiFini=true
		exit 1
	fi
}

#méthode qui a pour but d'écrire dans le terminal du joueur les cartes jouées par les autres joueurs durant la partie.
ecrireCarteJouer()
{
	while [ $partieFini == "false" ]
	do
		#si le fichier tmp/carteJouer n'est pas vide
		if [ $(wc -w tmp/carteJouer | cut -d" " -f1) != 0 ];
		then
			#on écrit la carte jouée par le joueur
			cat tmp/carteJouer
			
			#on attend que tous les joueurs aient écrits le message
			sleep 1
			cat "" > tmp/carteJouer
		fi
	done
}

#méthode qui va permettre au joueur de démarrer sa partie.
startGame()
{
	#avant de commencer la partie on attend les cartes
	waitCartes
	
	#quand on a recu les cartes on attend le top départ
	waitTopDepart
	
	#on lance la méthode en tache de fond pour afficher chez tout les joueur humain que tel joueur a joué telle carte
	#ecrireCarteJouer &
	
	while [ $partieFini == "false" ]
	do
		#on vérifie si le joueur a encore des cartes
		if (( ${#cartesJoueur[*]} == 0 ));
		then
			echo Vous avez jouer toutes vos cartes, attendez la fin de la manche.
			
			#apres chaque manche on verifie si la partie est fini
			finGame 
			
			onAttend=true
			while [ $onAttend == "true" ]
			do
				#si le fichier tmp/redistribuer n'est pas vide, redistribution des cartes
				if [ $(wc -w tmp/redistribuer | cut -d" " -f1) != 0 ];
				then
					#on reverifie ici avant de redistribuer les cartes
					finGame 
					echo "" > tmp/redistribuer
					onAttend=false
					waitCartes		#on attend de nouvelles cartes
				fi
			done
		fi
		
		echo Vos cartes sont : ${cartesJoueur[*]}
		echo Choissisez une carte a jouer :
		read carteCourante 
		
		#parcours les cartes du joueur afin de vérifer que la carte jouée est bien presente dans son jeu
		for i in $(eval echo {0..$((${#cartesJoueur[*]} - 1))});
		do
			if (( "$carteCourante" == ${cartesJoueur[$i]} ));
			then			
				#écrit la valeur de la carte jouée dans le fichier tmp/carteAJouer
				echo $carteCourante > tmp/carteAJouer
				
				#ecrit le num du joueur dans dans le fichier tmp/numJoueur
				echo $numeroJoueur > tmp/numJoueur
				
				onAttend=true
				while [ $onAttend == "true" ]
				do
					#permets la connexion au socket ouvert sur le processus du gestionnaire du jeu, et indique que le joueur a joué tel carte.
					#"2> /dev/null" permet de rediriger la sortie des erreurs car si le socket n'arrive pas à se connecter dans le cas ou le socket n'est pas en lecture dans le processus du gestionnaire du jeu. Alors on aura une erreur "Connexion refusé".
					echo "Joueur $numeroJoueur a jouer la carte $carteCourante" | nc localhost 9093 2> /dev/null | echo "Carte joue." & onAttend=false
				done
			
				#on enleve la carte des cartes disponible pour le joueur
				#on n'utilise pas sa : cartesJoueur=( "${cartesJoueur[*]/$carteCourante" )
				#car si la carte a retirer est 1, ça enlève tous les 1 
				#si on a les cartes(10 15 1 78 41) et qu'on veut jouer 1, on va avoir (0 5 78 4)
				retireCarte $carteCourante
				
				#on sort de force de la boucle car dans le cas où on retire la première  
				#carte du tableau, le if va comparer des cases qui n'existe plus  					#et va donc donner une erreur
				break
			fi
		done
	done
}

#on lance la méthode qui va faire jouer le joueur et qui va appeler toutes les autres fonctions
startGame
